# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Instance health', type: :request do
  let(:path) { '/inclamo/health' }
  let(:status_file) { Tempfile.new(['backup-status', '.json']) }
  let(:worker_key) { "inclamo-health-spec:#{SecureRandom.hex(4)}" }

  around do |example|
    with_modified_env INCLAMO_BACKUP_STATUS_FILE: status_file.path, INCLAMO_HEALTH_DISK_PATH: nil do
      example.run
    end
  end

  before do
    record
    beat
    # The runner's own disk is not what is tested; `df` itself is read in
    # custom/spec/lib/inclamo/health_spec.rb.
    allow(Inclamo::Health).to receive(:disk_free_ratio).and_return(0.5)
  end

  after do
    Sidekiq.redis do |conn|
      conn.call('SREM', 'processes', worker_key)
      conn.call('DEL', worker_key)
    end
    status_file.close!
  end

  # What the backup and restore-test scripts leave on the host.
  def record(backup: 1.hour.ago, restore_test: 1.day.ago)
    File.write(status_file.path, JSON.generate({ last_backup_at: backup&.utc&.iso8601, last_restore_test_at: restore_test&.utc&.iso8601 }.compact))
  end

  # A worker in Sidekiq's registry, written the way its heartbeat writes it.
  def beat(at = Time.current)
    info = { hostname: 'health-spec', started_at: at.to_f, pid: 1, tag: '', concurrency: 1, queues: ['default'], labels: [], identity: worker_key }
    Sidekiq.redis do |conn|
      conn.call('SADD', 'processes', worker_key)
      conn.call('HSET', worker_key, 'info', JSON.generate(info), 'busy', '0', 'beat', at.to_f.to_s, 'quiet', 'false', 'rss', '0', 'rtt_us', '0')
      conn.call('EXPIRE', worker_key, 60)
    end
  end

  def expect_failing(*names)
    get path

    expect(response).to have_http_status(:service_unavailable)
    expect(response.parsed_body).to eq(
      'status' => 'failing', 'failing' => names,
      'overlay_version' => Inclamo::Overlay.version, 'chatwoot_version' => Chatwoot.config[:version]
    )
  end

  it 'answers 200 without sign-in when every check is good, after a real query' do
    queries = []
    subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') { |*, payload| queries << payload[:sql] }

    get path
    ActiveSupport::Notifications.unsubscribe(subscriber)

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq(
      'status' => 'ok', 'failing' => [],
      'overlay_version' => Inclamo::Overlay.version, 'chatwoot_version' => Chatwoot.config[:version]
    )
    expect(response.headers['Cache-Control']).to include('no-store')
    expect(queries).to include('SELECT 1')
    expect(Inclamo::Health.worker_beats).to include(be_within(5).of(Time.current.to_f))
  end

  it 'names the versions that run' do
    get path

    expect(response.parsed_body['overlay_version']).to eq(Rails.root.join('custom/INCLAMO_VERSION').read.strip)
    expect("v#{response.parsed_body['chatwoot_version']}").to eq(Rails.root.join('custom/CHATWOOT_VERSION').read.strip)
  end

  describe 'a failing check gives 503 with its name' do
    it 'database: the query fails' do
      allow(Inclamo::Health).to receive(:query_database).and_raise(ActiveRecord::ConnectionNotEstablished)

      expect_failing('database')
    end

    it 'database: the query answers something else' do
      allow(Inclamo::Health).to receive(:query_database).and_return(nil)

      expect_failing('database')
    end

    it 'redis: no connection' do
      allow(Inclamo::Health).to receive(:ping_redis).and_raise(Redis::CannotConnectError)

      expect_failing('redis')
    end

    it 'workers: no Sidekiq process is registered' do
      allow(Inclamo::Health).to receive(:worker_beats).and_return([])

      expect_failing('workers')
    end

    it 'workers: the last beat is old' do
      allow(Inclamo::Health).to receive(:worker_beats).and_return([2.minutes.ago.to_f])

      expect_failing('workers')
    end

    it 'backup: the last one is older than 26 hours' do
      record(backup: 27.hours.ago)

      expect_failing('backup')
    end

    it 'backup: none was recorded' do
      record(backup: nil)

      expect_failing('backup')
    end

    it 'restore_test: the last one is older than 35 days' do
      record(restore_test: 36.days.ago)

      expect_failing('restore_test')
    end

    it 'backup and restore_test: the status file is missing' do
      with_modified_env INCLAMO_BACKUP_STATUS_FILE: "#{status_file.path}.missing" do
        expect_failing('backup', 'restore_test')
      end
    end

    it 'backup and restore_test: the status file cannot be read as JSON' do
      File.write(status_file.path, 'not json')

      expect_failing('backup', 'restore_test')
    end

    it 'disk: 15 % free or less' do
      allow(Inclamo::Health).to receive(:disk_free_ratio).and_return(0.15)

      expect_failing('disk')
    end

    it 'disk: the free space cannot be read' do
      allow(Inclamo::Health).to receive(:disk_free_ratio).and_raise(Errno::ENOENT)

      expect_failing('disk')
    end

    it 'names every failing check at once' do
      allow(Inclamo::Health).to receive(:worker_beats).and_return([])
      allow(Inclamo::Health).to receive(:disk_free_ratio).and_return(0.01)
      record(backup: 3.days.ago)

      expect_failing('workers', 'backup', 'disk')
    end
  end

  it 'stays good just inside the limits' do
    record(backup: 25.hours.ago, restore_test: 34.days.ago)
    allow(Inclamo::Health).to receive(:disk_free_ratio).and_return(0.16)

    get path

    expect(response).to have_http_status(:ok)
  end

  it 'reads a time written as seconds since the epoch' do
    File.write(status_file.path, JSON.generate(last_backup_at: 1.hour.ago.to_i, last_restore_test_at: 40.days.ago.to_i))

    expect_failing('restore_test')
  end

  describe 'what the body does not hold' do
    let(:secrets) do
      # Read by nothing while a request runs, so the examples change no behavior.
      { SMTP_PASSWORD: 'synthetic-smtp-password', STORAGE_SECRET_ACCESS_KEY: 'synthetic-storage-key' }
    end

    before do
      account = create(:account, name: 'Synthetic Merchant Ltd')
      create(:user, account: account, name: 'Synthetic Agent', email: 'agent@example.test')
      create(:contact, account: account, name: 'Synthetic Customer', email: 'customer@example.test')
    end

    def expect_nothing_else
      body = response.body
      expect(response.parsed_body.keys).to contain_exactly('status', 'failing', 'overlay_version', 'chatwoot_version')
      expect(response.parsed_body['failing'] - Inclamo::Health::CHECKS.map(&:to_s)).to be_empty
      ['Synthetic', 'example.test', 'synthetic-', Rails.application.secret_key_base, status_file.path, worker_key].each do |text|
        expect(body).not_to include(text)
      end
      # No number but the two versions: no count, no age, no size.
      expect(body.gsub(Inclamo::Overlay.version, '').gsub(Chatwoot.config[:version], '')).not_to match(/\d/)
    end

    it 'when every check is good' do
      with_modified_env(secrets) { get path }

      expect(response).to have_http_status(:ok)
      expect_nothing_else
    end

    it 'when checks fail, not even the text of their errors' do
      allow(Inclamo::Health).to receive(:query_database)
        .and_raise(ActiveRecord::ConnectionNotEstablished, 'connection to synthetic-host failed: password=synthetic-postgres-password')
      allow(Inclamo::Health).to receive(:ping_redis)
        .and_raise(Redis::CannotConnectError, 'redis://:synthetic-redis-password@synthetic-host:6379')
      record(backup: 3.days.ago, restore_test: 90.days.ago)

      with_modified_env(secrets) { get path }

      expect(response).to have_http_status(:service_unavailable)
      expect(response.parsed_body['failing']).to eq(%w[database redis backup restore_test])
      expect_nothing_else
    end
  end
end
