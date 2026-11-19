# frozen_string_literal: true

# Keeps the one-time entry address's token (docs/app-admin-entry.md §2) out of
# every log: a request for /inclamo/entry/<token> continues as a request for
# /inclamo/entry, with the token in the Rack environment under TOKEN, before
# the request log, the router, Rack::Attack or an error report see its path.
# Every answer of the address is marked not to be cached and to send no
# referrer. It sits outside every other middleware.
class InclamoEntryPath
  PATH = '/inclamo/entry'
  TOKEN = 'inclamo.entry.token'
  WITH_TOKEN = %r{\A/inclamo/entry/([^/]*)/?\z}
  ANSWER_HEADERS = { 'referrer-policy' => 'no-referrer', 'cache-control' => 'no-store' }.freeze

  def initialize(app)
    @app = app
  end

  def call(env)
    match = WITH_TOKEN.match(env['PATH_INFO'].to_s)
    return @app.call(env) unless match || env['PATH_INFO'] == PATH

    if match
      env[TOKEN] = match[1]
      env['PATH_INFO'] = PATH
      %w[REQUEST_URI REQUEST_PATH ORIGINAL_FULLPATH].each { |name| env[name] = PATH if env.key?(name) }
    end
    status, headers, body = @app.call(env)
    ANSWER_HEADERS.each { |name, value| headers[name] = value }
    [status, headers, body]
  end
end
