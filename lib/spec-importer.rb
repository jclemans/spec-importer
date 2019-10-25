require 'spec-importer/version'
require 'spec-importer/railtie' if defined?(Rails)

module SpecImporter
  def self.create_object(sheet)
    script_args = []
    model_name = sheet.simple_rows.first['B']
    fae_generator_type = sheet.simple_rows.to_a[8]['B']
    parent_class = sheet.simple_rows.to_a[8]['D']

    # Exit if the current model already was created.
    return if Object.const_defined?(model_name)

    sheet.simple_rows.each_with_index do |row, index|
      next if row['A'] == 'skip'
      if index > 10 && (row['A'].blank? || row['B'].blank?)
        puts "Nothing to read in column A or B. Exiting the importer."
        break
      end

      if index == 10
        script_args <<  "rails g fae:#{fae_generator_type} #{model_name}" if index == 10
      elsif index > 10
        puts "Adding: #{row['A']}:#{row['B']}"
        script_args << "#{row['A']}:#{row['B']}" << (":index" if row['C'] == true)
      else
        next
      end
    end
    return script_args
  end

  def self.update_object(sheet)
    script_args = []
    model_name = sheet.simple_rows.first['B']
    fae_generator_type = sheet.simple_rows.to_a[8]['B']
    parent_class = sheet.simple_rows.to_a[8]['D']

    sheet.simple_rows.each_with_index do |row, index|
      next if row['A'] == 'skip'
      if index > 10 && (row['A'].blank? || row['B'].blank?)
        puts "Nothing to read in column A or B. Exiting the importer."
        break
      end

      if index > 10
        if row['E'] == 'Add'
          puts "Adding new field: #{row['A']}:#{row['B']}"
          script_args << "#{row['A']}:#{row['B']}"
        elsif row['E'] == 'Remove'
          puts "Removing field: #{row['A']}:#{row['B']}"
          # generate a migration to remove the current row's column from the db
          script_args <<  "rails g migration Remove#{row['A']}From#{model_name} #{row['A']}:#{row['B']}"

          # comment out this row's field for static page forms
          if fae_generator_type == 'Fae::StaticPage'
            thor_action(
              :inject_into_file,
              "app/views/admin/content_blocks/#{model_name.underscore.gsub('_page', '')}.html.slim",
              '/ ',
              before: "= #{self.find_page_field_type(row['B'])} f, :#{row['A']}"
            )
          # comment out this row's field for regular object forms
          else
            thor_action(
              :inject_into_file,
              "app/views/admin/#{model_name.underscore.pluralize}/_form.html.slim",
              '/ ',
              before: "= #{self.find_object_field_type(row['B'])} f, :#{row['A']}"
            )
          end
        elsif row['E'] == 'Update'
          # Changes are tricky to automate since we could be changing form field names, validations, db column names or types, etc.
          # To start lets inject a "TODO" note on the model to callout needed changes
          thor_action(
            :inject_into_file,
            "app/models/#{model_name.underscore}.rb",
            "# TODO: CMS spec changes for this row:\n# #{row}\n",
            before: "class #{model_name}"
          )
        else
          # No changes to this row. It already exists in the app, so just skip it
          next
        end

      end

    end
    return script_args
  end

  def self.delete_object(sheet)
    script_args = []
    model_name = sheet.simple_rows.first['B']
    fae_generator_type = sheet.simple_rows.to_a[8]['B']

    # Disable admin route for this object
    thor_action(
      :inject_into_file,
      'config/routes.rb', '# ',
      before: "resources :#{model_name.underscore.pluralize}"
    )
    # Add a note to remove admin navigation related to the object.
    thor_action(
      :inject_into_file,
      'app/models/concerns/fae/navigation_concern.rb',
      "\t\t\t# TODO: disable nav for #{model_name}\n",
      after: "def structure\n"
    )

    # Optional if you want to fully destroy the model instead of just disabling/hiding:
    # > Create a migration to remove the object table
    # sh "rails g migration Remove#{response[:model_name]}"
    # > Remove the model, fae views, and controllers
    # sh "rails destroy fae:#{response[:fae_generator_type]} #{response[:model_name]}"
    script_args
  end

  def self.find_page_field_type(column_b)
    case column_b
    when 'image'
      'fae_image_form'
    when 'file'
      'fae_file_form'
    else
      'fae_content_form'
    end
  end

  def self.find_object_field_type(column_b)
    case column_b
    when 'image'
      'fae_image_form'
    when 'file'
      'fae_file_form'
    when 'date'
      'fae_datepicker'
    when 'references'
      'fae_association'
    else
      'fae_input'
    end
  end

end
