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
      script_args[:fae] << "--parent-model=#{parent_class}"
    end
    # Use the puts for debugging, sh for running
    # STDOUT.puts "#{script_args.join(' ')}" if !script_args.empty?
    sh "#{script_args[:fae].join(' ')}"
    script_args[:joins].each do |generate_join_string|
      sh generate_join_string
    end
    sh 'rake db:migrate'
    # then restart the application
    sh 'docker-compose down'
    sh 'docker-compose up'
  end

  task :update_form => :environment do
    desc 'Read and import field labels and helper text from a xlsx cms spec file.'

    STDOUT.puts "Enter path to xlsx file in project (ex. tmp/file.xlsx)"
    path = STDIN.gets.chomp
    creek = Creek::Book.new path

    STDOUT.puts(creek.sheets.to_a.map.with_index { |obj, i| "#{i}: #{obj.name}" })
    STDOUT.puts "Select sheet to import: [0-#{creek.sheets.length}]"
    num = STDIN.gets.chomp
    sheet = creek.sheets[num.to_i]
    model = sheet.simple_rows.first['B']
    fae_generator_type = sheet.simple_rows.to_a[8]['B']

    sheet.simple_rows.each_with_index do |row, index|
      next if index < 11
      if row['F'].blank?
        STDOUT.puts "No form label present in column F. Exiting the form/helper updater."
        break
      end
      # add labels for each form field
      thor_action(
        :gsub_file,
        "app/views/admin/#{model.underscore.pluralize}/_form.html.slim",
        /, :":#{row['A']}"/, ", :#{row['A']}, label: '#{row["F"]}'"
      )

      # add helper text after the label
      thor_action(
        :inject_into_file,
        "app/views/admin/#{model.underscore.pluralize}/_form.html.slim",
        ", helper_text: '#{row["J"]}'",
        after: ":#{row['A']}, label: '#{row["F"]}'"
      )

      # TODO: add a generate join table and migrate to the create and update object process
      if row['B'] == 'join'
        # add form field for the join association.
        thor_action(
          :inject_into_file,
          "app/views/admin/#{model.underscore.pluralize}/_form.html.slim",
          "\t\t= fae_multiselect f, :#{row['A'].split.join('_')} # optionally a fae_grouped_select field",
          after: "main.content\n"
        )
      end

      if row['B'] == 'image' && fae_generator_type == 'scaffold'
        # add image form field details
        thor_action(
          :inject_into_file,
          "app/views/admin/#{model.underscore.pluralize}/_form.html.slim",
          "label: '#{row["F"]}', required: '#{row["H"]}', helper_text: '#{row["K"]}'",
          after: "= fae_image_form f, :#{row['A']}"
        )
      end
      # if required is true, add presence validations to object model
      if row['H'] == true
        thor_action(
          :inject_into_file,
          "app/models/#{model.underscore}.rb",
          "\tvalidates_presence_of :#{row['A']}\n",
          after: "include Fae::BaseModelConcern\n"
        )
      end

      # if markdown is true, add it to the form
      if row['I'] == true
        thor_action(
          :inject_into_file,
          "app/views/admin/#{model.underscore.pluralize}/_form.html.slim",
          ", markdown: true", after: row['A'], force: true
        )
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