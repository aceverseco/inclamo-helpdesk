# frozen_string_literal: true

require 'rails_helper'

# custom/CHATWOOT_FILES: the files of Chatwoot the overlay stands in for. The
# record is checked against Chatwoot's sources by scripts/assemble.sh; here the
# assembled application is checked against the record.
RSpec.describe 'Chatwoot files the overlay stands in for' do # rubocop:disable RSpec/DescribeClass
  entries = Rails.root.join('custom/CHATWOOT_FILES').readlines(chomp: true)
                 .reject { |line| line.strip.empty? || line.start_with?('#') }
                 .map(&:split)
  replaced = entries.select { |entry| entry.size == 2 }.map { |entry| entry[1] }
  views = entries.select { |entry| entry.size == 3 && entry[1].start_with?('app/views/') }

  it 'records each file once' do
    paths = entries.map { |entry| entry[1] }

    expect(paths).to eq(paths.uniq)
  end

  it "keeps Chatwoot's own file, unchanged, beside every file put in its place" do
    replaced.each do |path|
      kept = path.sub(/\.(\w+)\z/, '.chatwoot.\1')

      expect(Rails.root.join(path)).to exist, "#{path} is not in the assembled tree"
      expect(Rails.root.join(kept)).to exist, "#{kept} was not kept"
    end
  end

  it "finds the overlay's templates before Chatwoot's" do
    expect(ApplicationController.view_paths.first.to_s).to eq(Rails.root.join('custom/app/views').to_s)
  end

  it "leaves Chatwoot's template where it is and has the overlay's under the same name" do
    views.each do |_blob, path, ours|
      expect(ours).to eq("custom/#{path}")
      expect(Rails.root.join(path)).to exist
      expect(Rails.root.join(ours)).to exist
    end
  end

  it "resolves each of these templates to the overlay's file" do
    lookup = ApplicationController.new.lookup_context

    views.each do |_blob, path, ours|
      prefix, name = path.delete_prefix('app/views/').sub(/\.html\.erb\z/, '').then { |logical| [File.dirname(logical), File.basename(logical)] }
      partial = name.start_with?('_')
      template = lookup.find(name.delete_prefix('_'), [prefix], partial)

      expect(template.identifier).to eq(Rails.root.join(ours).to_s)
    end
  end
end
