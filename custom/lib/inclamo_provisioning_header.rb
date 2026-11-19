# frozen_string_literal: true

# Marks every answer of an address under /inclamo/provisioning/ on an
# installation with provisioning turned on, whatever produced it: the
# provisioning controllers, the request limits, an address that does not exist
# and an error page. A `404` without the mark is an installation (or something
# in front of it) that has no provisioning. It sits outside every other
# middleware, so nothing answers past it.
class InclamoProvisioningHeader
  def initialize(app)
    @app = app
  end

  def call(env)
    status, headers, body = @app.call(env)
    if env['PATH_INFO'].to_s.start_with?(Inclamo::Provisioning::PATH_PREFIX) && Inclamo::Provisioning.enabled?
      headers[Inclamo::Provisioning::HEADER] = '1'
    end
    [status, headers, body]
  end
end
