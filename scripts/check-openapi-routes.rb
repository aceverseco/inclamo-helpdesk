# frozen_string_literal: true

# Every route of the overlay is either described in custom/swagger/inclamo.yml
# or listed, with a reason, in custom/swagger/excluded-routes.yml; and every
# path of inclamo.yml is served by a route. The routes are drawn by Rails
# itself: custom/config/routes.rb is evaluated into a fresh
# ActionDispatch::Routing::RouteSet, as custom/config/overlay.rb evaluates it
# into Chatwoot's, with the store app's routes drawn as on an installation
# where the provisioning secret is set. No database, no booted app.
#
#   cd build/chatwoot && bundle exec ruby ../../scripts/check-openapi-routes.rb
#   ... check-openapi-routes.rb --self-test   (the check refuses what it should)
#
# Rails draws `resources ... :update` as PATCH and PUT to the same action;
# describing one of the two covers its twin.
#
# Also checks that inclamo.yml carries the pinned versions: info.version is
# custom/INCLAMO_VERSION and x-chatwoot-version is custom/CHATWOOT_VERSION.

require 'action_dispatch'
require 'yaml'

module OpenapiRoutes
  ROOT = File.expand_path('..', __dir__)
  ROUTES = File.join(ROOT, 'custom/config/routes.rb')
  SPEC = File.join(ROOT, 'custom/swagger/inclamo.yml')
  EXCLUDED = File.join(ROOT, 'custom/swagger/excluded-routes.yml')
  METHODS = %w[get put post delete patch options head trace].freeze

  Route = Struct.new(:verb, :path, :endpoint)

  module_function

  # The routes custom/config/routes.rb draws, with paths in OpenAPI form.
  def routes(source = File.read(ROUTES))
    stub_provisioning
    set = ActionDispatch::Routing::RouteSet.new
    set.draw { instance_eval(source, ROUTES) }
    set.routes.flat_map do |route|
      verbs = route.verb.to_s.split('|').reject(&:empty?)
      raise "#{route.path.spec}: a route without a verb cannot be checked" if verbs.empty?

      path = openapi_path(route.path.spec.to_s)
      endpoint = "#{route.defaults[:controller]}##{route.defaults[:action]}"
      verbs.map { |verb| Route.new(verb.upcase, path, endpoint) }
    end
  end

  # /a/:id(.:format) -> /a/{id}
  def openapi_path(spec)
    path = spec.sub(/\(\.:format\)\z/, '')
    raise "#{spec}: optional segments or globs are not supported by this check" if path.match?(/[()*]/)

    path.gsub(/:(\w+)/, '{\1}')
  end

  # The overlay draws the store app's routes only where the operator set the
  # shared secret. Here they are always drawn, so that they are checked too.
  def stub_provisioning
    return if defined?(::Inclamo::Provisioning) && ::Inclamo::Provisioning.respond_to?(:enabled?)

    inclamo = defined?(::Inclamo) ? ::Inclamo : Object.const_set(:Inclamo, Module.new)
    provisioning = inclamo.const_defined?(:Provisioning, false) ? inclamo::Provisioning : inclamo.const_set(:Provisioning, Module.new)
    provisioning.define_singleton_method(:enabled?) { true }
  end

  def load_yaml(path)
    YAML.safe_load(File.read(path), permitted_classes: [], aliases: false, filename: path)
  end

  def documented(spec)
    spec.fetch('paths', {}).flat_map do |path, item|
      (item.keys & METHODS).map { |method| [method.upcase, path] }
    end
  end

  def excluded(list)
    Array(list && list['routes']).map do |entry|
      { verb: entry['verb'].to_s.upcase, path: entry['path'].to_s, reason: entry['reason'].to_s.strip }
    end
  end

  # Every problem, as a sentence that names the route or the path.
  def problems(routes:, spec:, excluded:, versions: nil)
    found = []
    docs = documented(spec)
    skipped = excluded
    doc_keys = docs.to_h { |key| [key, true] }
    skip_keys = skipped.to_h { |entry| [[entry[:verb], entry[:path]], true] }
    served = routes.to_h { |route| [[route.verb, route.path], route] }

    # PATCH and PUT drawn by one `update`: one described covers the other.
    twin = lambda do |route|
      other = { 'PATCH' => 'PUT', 'PUT' => 'PATCH' }[route.verb]
      other && served[[other, route.path]]&.endpoint == route.endpoint ? [other, route.path] : nil
    end
    covered = ->(key, route) { doc_keys[key] || ((pair = twin.call(route)) && doc_keys[pair]) }
    skipped_route = ->(key, route) { skip_keys[key] || ((pair = twin.call(route)) && skip_keys[pair]) }

    routes.each do |route|
      key = [route.verb, route.path]
      described = covered.call(key, route)
      listed = skipped_route.call(key, route)
      if described && listed
        found << "#{route.verb} #{route.path} (#{route.endpoint}) is both described in custom/swagger/inclamo.yml and listed in custom/swagger/excluded-routes.yml"
      elsif !described && !listed
        found << "#{route.verb} #{route.path} (#{route.endpoint}) is neither described in custom/swagger/inclamo.yml nor listed in custom/swagger/excluded-routes.yml"
      end
    end

    docs.each do |verb, path|
      next if served[[verb, path]]

      found << "custom/swagger/inclamo.yml describes #{verb} #{path}, which no route of custom/config/routes.rb serves"
    end

    seen = {}
    skipped.each do |entry|
      key = [entry[:verb], entry[:path]]
      found << "custom/swagger/excluded-routes.yml lists #{entry[:verb]} #{entry[:path]} twice" if seen[key]
      seen[key] = true
      found << "custom/swagger/excluded-routes.yml lists #{entry[:verb]} #{entry[:path]} without a reason" if entry[:reason].empty?
      next if served[key]

      found << "custom/swagger/excluded-routes.yml lists #{entry[:verb]} #{entry[:path]}, which no route of custom/config/routes.rb serves"
    end

    if versions
      info = spec['info'] || {}
      if info['version'] != versions[:inclamo]
        found << "custom/swagger/inclamo.yml info.version is #{info['version'].inspect}, custom/INCLAMO_VERSION is #{versions[:inclamo].inspect}"
      end
      if info['x-chatwoot-version'] != versions[:chatwoot]
        found << "custom/swagger/inclamo.yml info.x-chatwoot-version is #{info['x-chatwoot-version'].inspect}, custom/CHATWOOT_VERSION is #{versions[:chatwoot].inspect}"
      end
    end
    found
  end

  def versions
    { inclamo: File.read(File.join(ROOT, 'custom/INCLAMO_VERSION')).strip,
      chatwoot: File.read(File.join(ROOT, 'custom/CHATWOOT_VERSION')).strip }
  end

  def check
    drawn = routes
    spec = load_yaml(SPEC)
    list = excluded(load_yaml(EXCLUDED))
    found = problems(routes: drawn, spec: spec, excluded: list, versions: versions)
    if found.empty?
      described = drawn.count { |route| documented(spec).include?([route.verb, route.path]) }
      puts "openapi routes: #{drawn.size} routes drawn, #{described} described, #{list.size} excluded, " \
           "#{drawn.size - described - list.size} covered as PATCH/PUT twins"
      return true
    end

    warn found.map { |problem| "openapi routes: #{problem}" }
    false
  end

  # The check itself: a new route nobody described, a described path no
  # route serves and a stale exclusion are each named; the real files pass.
  def self_test
    source = File.read(ROUTES)
    spec = load_yaml(SPEC)
    list = excluded(load_yaml(EXCLUDED))
    failures = []
    expect = lambda do |label, found, needle|
      failures << "#{label}: expected a problem naming #{needle.inspect}, got #{found.inspect}" unless found.any? { |line| line.include?(needle) }
    end

    added = routes("#{source}\nget '/inclamo/self-test/:id', to: 'inclamo/health#show'\n")
    expect.call('undescribed route', problems(routes: added, spec: spec, excluded: list), 'GET /inclamo/self-test/{id} (inclamo/health#show) is neither described')

    extra = Marshal.load(Marshal.dump(spec))
    extra['paths']['/inclamo/nowhere'] = { 'get' => { 'responses' => { '200' => { 'description' => 'x' } } } }
    expect.call('described path without a route', problems(routes: routes(source), spec: extra, excluded: list), 'describes GET /inclamo/nowhere, which no route')

    stale = list + [{ verb: 'POST', path: '/inclamo/gone', reason: 'x' }]
    expect.call('stale exclusion', problems(routes: routes(source), spec: spec, excluded: stale), 'lists POST /inclamo/gone, which no route')

    unexplained = list.map(&:dup).tap { |entries| entries.first[:reason] = '' }
    expect.call('exclusion without a reason', problems(routes: routes(source), spec: spec, excluded: unexplained), 'without a reason')

    both = list + [{ verb: 'GET', path: '/inclamo/health', reason: 'x' }]
    expect.call('described and excluded', problems(routes: routes(source), spec: spec, excluded: both), 'GET /inclamo/health (inclamo/health#show) is both')

    bumped = Marshal.load(Marshal.dump(spec)).tap { |doc| doc['info']['version'] = '0.0.0-self-test' }
    expect.call('version drift', problems(routes: routes(source), spec: bumped, excluded: list, versions: versions), 'info.version')

    real = problems(routes: routes(source), spec: spec, excluded: list, versions: versions)
    failures << "the repository's own files: #{real.inspect}" unless real.empty?

    if failures.empty?
      puts 'openapi routes self-test: every refusal is named, the repository passes'
      return true
    end

    warn failures.map { |failure| "openapi routes self-test: #{failure}" }
    false
  end
end

exit(ARGV.include?('--self-test') ? OpenapiRoutes.self_test : OpenapiRoutes.check) if $PROGRAM_NAME == __FILE__
