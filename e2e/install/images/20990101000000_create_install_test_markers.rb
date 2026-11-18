# frozen_string_literal: true

# Only in the images the install tests build (e2e/install/images): a table
# whose presence shows that an upgrade ran the overlay's migrations, and whose
# absence shows that a rollback brought the pre-upgrade database back.
class CreateInstallTestMarkers < ActiveRecord::Migration[7.1]
  def change
    create_table :install_test_markers, &:timestamps
  end
end
