# frozen_string_literal: true

# Inclamo Helpdesk: the one file placed in Chatwoot's lib/tasks.
# Rake tasks are collected before the application initializes, so the
# overlay's tasks cannot be registered from an initializer.
Dir[File.expand_path('../../custom/lib/tasks/**/*.rake', __dir__)].each { |file| load file }
