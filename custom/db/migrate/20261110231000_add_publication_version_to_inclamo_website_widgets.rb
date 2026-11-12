# frozen_string_literal: true

class AddPublicationVersionToInclamoWebsiteWidgets < ActiveRecord::Migration[7.0]
  def change
    add_column :inclamo_website_widgets, :publication_version, :bigint, null: false, default: 0
  end
end
