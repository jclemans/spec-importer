require 'rake'
require 'creek'
require 'thor'

namespace :sheet do
  task :import, [:file_path, :sheet_number] => :environment do |t, args|
    desc 'Add, Remove, or Update Fae powered CMS objects from an xlsx file.'
    if args.count == 2
      # Try getting the file path and sheet from args if passed in
      path               = args[:file_path]
      num                = args[:sheet_number]
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

    sheet              = creek.sheets[num.to_i]
    object_action      = sheet.simple_rows.first['D']
    parent_class       = sheet.simple_rows.to_a[8]['D']
    fae_generator_type = sheet.simple_rows.to_a[8]['B']

    case object_action
    when 'Create'
      script_args = SpecImporter.create_object(sheet)
    when 'Update'
      script_args = SpecImporter.update_object(sheet)
    when 'Remove'
      script_args = SpecImporter.delete_object(sheet)
    else
      abort 'No action was selected for this object. Task aborted.'
    end

    if fae_generator_type == 'nested_scaffold' && parent_class.present?
      script_args << "--parent-model=#{parent_class}"
    end
    # puts for debugging, sh for running
    STDOUT.puts "#{script_args.join(' ')}" if !script_args.empty?
    # sh "#{script_args.join(' ')}" if !script_args.empty?
  end

  task :update_object_form => :environment do
    desc 'Read and import field labels and helper text from a xlsx cms spec file.'

    STDOUT.puts "Enter path to xlsx file in project (ex. tmp/file.xlsx)"
    path = STDIN.gets.chomp
    creek = Creek::Book.new path

    STDOUT.puts(creek.sheets.to_a.map.with_index { |obj, i| "#{i}: #{obj.name}" })
    STDOUT.puts "Select sheet to import: [0-#{creek.sheets.length}]"
    model = nil
    num = STDIN.gets.chomp
    sheet = creek.sheets[num.to_i]

    sheet.simple_rows.each_with_index do |row, index|
      model = row['B'] if index == 0
      if row.length > 0 && index > 10 && row['A'].present?
        if row['F'] == 'fae_image_form'
          # add image association and form field
          thor_action(:inject_into_file, "app/models/#{model.underscore}.rb", "\thas_fae_image :#{row['A']}\n", after: "include Fae::BaseModelConcern\n")
          thor_action(:inject_into_file, "app/views/admin/#{model.underscore.pluralize}/_form.html.slim", "\n\t\t= fae_image_form f, :#{row['A']}", after: 'main.content')
        end
        if row['G'] == true
          # add presence validations to object model
          thor_action(:inject_into_file, "app/models/#{model.underscore}.rb", "\tvalidates_presence_of :#{row['A']}\n", after: "include Fae::BaseModelConcern\n")
        end
        if row['J'].present?
          # if there is helper text, add it to the form after the attribute name
          thor_action(:inject_into_file, "app/views/admin/#{model.underscore.pluralize}/_form.html.slim", ", helper_text: '#{row["J"]}'", after: ":#{row['A']}")
        end
        if row['H'] == true
          # if markdown is true, add it to the form
          thor_action(:inject_into_file, "app/views/admin/#{model.underscore.pluralize}/_form.html.slim", ", markdown: true", after: row['A'], force: true)
        end
      elsif row.length == 0
        puts "Empty row found. Exiting scan of this sheet."
        break
      end
    end
  end

  class ThorAction < Thor
    include Thor::Actions
  end

  def thor_action(*args)
    ThorAction.new.send(*args)
  end
end