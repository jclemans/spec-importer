class SpecImporter::Railtie < Rails::Railtie
  rake_tasks do
    load 'tasks/tasks.rake'
  end
end
