# frozen_string_literal: true

# Bound support input before Rails parses or logs it. Buffering at this outer
# boundary also handles chunked requests without Content-Length consistently.
class InclamoSupportBodyLimit
  def initialize(app)
    @app = app
  end

  def call(env)
    path = env['PATH_INFO'].to_s
    return @app.call(env) unless path.start_with?('/inclamo/support/v1/') || path.match?(%r{\A/api/v1/accounts/\d+/inclamo/support/})

    limit = path.end_with?('/uploads') ? (Inclamo::Support::MAX_BYTES * 4 / 3 + 65_536) : (Inclamo::Support::MAX_BODY * 4 + 65_536)
    return too_large if env['CONTENT_LENGTH'].to_i > limit

    if env['rack.input']
      body = +''.b
      while (chunk = env['rack.input'].read([65_536, limit - body.bytesize + 1].min)) && !chunk.empty?
        body << chunk
        return too_large if body.bytesize > limit
      end
      env['rack.input'] = StringIO.new(body)
    end
    @app.call(env)
  end

  private

  def too_large
    [413, { 'content-type' => 'application/json' }, ['{"error":"body_size"}']]
  end
end
