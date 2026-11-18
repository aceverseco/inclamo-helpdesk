# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Inclamo::Health do
  it 'reads the free share of a filesystem from df' do
    ratio = described_class.disk_free_ratio(Rails.root)

    expect(ratio).to be_a(Float)
    expect(ratio).to be_between(0.0, 1.0)
  end

  it 'fails the disk check for a path that does not exist' do
    with_modified_env INCLAMO_HEALTH_DISK_PATH: Rails.root.join('tmp/no-such-directory-of-the-health-spec').to_s do
      expect(described_class.passes?(:disk)).to be(false)
    end
  end

  it 'looks at the root of the container and at the status file of the host unless told otherwise' do
    with_modified_env INCLAMO_HEALTH_DISK_PATH: nil, INCLAMO_BACKUP_STATUS_FILE: nil do
      expect(described_class.disk_path).to eq('/')
      expect(described_class.status_file).to eq('/var/lib/inclamo-helpdesk/backup-status.json')
    end
  end

  it 'pings Redis and queries the database for real' do
    expect(described_class.ping_redis).to eq('PONG')
    expect(described_class.query_database).to eq(1)
  end
end
