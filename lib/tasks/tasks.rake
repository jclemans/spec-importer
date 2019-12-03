require 'rake'
require 'creek'
require 'thor'

namespace :import do
  task :object, [:file_path, :sheet_number, :object_action] => :environment do |t, args|
    desc 'Add, Remove, or Update Fae powered CMS objects from an xlsx file.'
    if args.count == 3
      # Try getting the file path and sheet from args if passed in
      path               = args[:file_path]
      num                = args[:sheet_number]
      object_action      = args[:object_action]
      creek              = Creek::Book.new path
    else
      # Use the command line prompt to set file path and choose sheet
      STDOUT.puts "Enter path to xlsx file in project (E.g. 'tmp/testfile.xlsx')."
      path = STDIN.gets.chomp
      creek = Creek::Book.new path
      STDOUT.puts(creek.sheets.to_a.map.with_index { |obj, i| "#{i}: #{obj.name}" })
      STDOUT.puts "Select sheet to import: [0-#{creek.sheets.length}]"
      num = STDIN.gets.chomp
    end

    sheet = creek.sheets[num.to_i]
    # if the sheet is the "ToRemoveList", read the list and remove objects we don't need
    if sheet.name.eql?('ToRemoveList')
      STDOUT.puts "Reading the ToRemoveList...\n"
      SpecImporter.remove_objects(sheet)
    # otherwise read the sheet and create or update object as specified in the sheet
    else
      parent_class       = sheet.simple_rows.to_a[8]['D']
      fae_generator_type = sheet.simple_rows.to_a[8]['B']
      # set the action from the sheet if it's not passed in via the task args
      object_action      ||= sheet.simple_rows.first['D']
      case object_action
      when 'Create'
        script_args = SpecImporter.create_object(sheet)
      when 'Update'
        script_args = SpecImporter.update_object(sheet)
      else
        abort 'No action was selected for this object. Task aborted.'
      end

      if fae_generator_type == 'nested_scaffold' && parent_class.present?
        script_args[:fae] << "--parent-model=#{parent_class}"
      end
      # run the generators
      sh "#{script_args[:fae].join(' ')}"
      script_args[:joins].each do |generate_join_string|
        sh generate_join_string
      end
      # run migrations
      sh 'rake db:migrate'
      # apply form labels, helper text, etc
      SpecImporter.update_form_fields(sheet)
    end
  end

  task :restart => :environment do
    desc 'restart the server after an import to get new routes/objects loaded'
    sh 'rails restart'
  end

  task :form => :environment do
    desc 'Read and import field labels and helper text from a xlsx cms spec file.'

    STDOUT.puts "Enter path to xlsx file in project (ex. tmp/file.xlsx)"
    path = STDIN.gets.chomp
    creek = Creek::Book.new path

    STDOUT.puts(creek.sheets.to_a.map.with_index { |obj, i| "#{i}: #{obj.name}" })
    STDOUT.puts "Select sheet to import: [0-#{creek.sheets.length}]"
    num = STDIN.gets.chomp
    sheet = creek.sheets[num.to_i]

    SpecImporter.update_form_fields(sheet)
  end

  class ThorAction < Thor
    include Thor::Actions
  end

  def thor_action(*args)
    ThorAction.new.send(*args)
  end
end