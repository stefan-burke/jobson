# Ensure workspace directories exist after app loads
Rails.application.config.after_initialize do
  FileStorageService.ensure_directories
end