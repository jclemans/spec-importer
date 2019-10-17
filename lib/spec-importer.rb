require 'spec-importer/version'
require 'spec-importer/railtie' if defined?(Rails)

module SpecImporter
  def self.create_object(sheet)
    response = {
      script_args: [],
      model_name: nil,
      fae_generator_type: nil,
      parent_class: nil
    }
    sheet.simple_rows.each_with_index do |row, index|
      next if row['A'] == 'skip'
      if index > 10 && (row['A'].blank? || row['B'].blank?)
        puts "Nothing to read in column A or B. Exiting the importer."
        break
      end

      response[:model_name] = row['B'] if index == 0

      # Let's check if this model already exists in the app. If so, output a message and exit the import.
      if Object.const_defined?(response[:model_name])
        puts "#{response[:model_name].underscore}.rb already exists! Change the spec action to 'Update' or 'Remove' if you want to modify this object."
        break
      end

      if index == 8
        response[:fae_generator_type] = row['B']
        response[:parent_class] = row['D']
      elsif index == 10
        response[:script_args] <<  "rails g fae:#{response[:fae_generator_type]} #{response[:model_name]}" if index == 10
      elsif index > 10
        puts "Adding: #{row['A']}:#{row['B']}"
        response[:script_args] << "#{row['A']}:#{row['B']}"
      else
        next
      end
    end
    return response
  end

  def update_object(sheet)
    # read rows and make changes as specified
    response = {
      script_args: [],
      model_name: nil,
      fae_generator_type: nil,
      parent_class: nil
    }
    sheet.simple_rows.each_with_index do |row, index|
      next if row['A'] == 'skip'
      if index > 10 && (row['A'].blank? || row['B'].blank?)
        puts "Nothing to read in column A or B. Exiting the importer."
        break
      end

      response[:model_name] = row['B'] if index == 0
      if index == 8
        response[:fae_generator_type] = row['B']
        response[:parent_class] = row['D']
      end
      response[:script_args] <<  "rails g fae:#{response[:fae_generator_type]} #{response[:model_name]}" if index == 10

      if index > 10
        if row['E'] == 'Add'
          puts "Adding: #{row['A']}:#{row['B']}"
          response[:script_args] << "#{row['A']}:#{row['B']}"
        elsif row['E'] == 'Remove'
          puts "Removing: #{row['A']}:#{row['B']}"
          # generate a migration to remove the current row's column from the db
          response[:script_args] <<  "rails g migration Remove#{row['A']}From#{response[:model_name]} #{row['A']}:#{row['B']}"

          # comment out this row's field for static page forms
          if response[:fae_generator_type] == 'Fae::StaticPage'
            thor_action(
              :inject_into_file,
              "app/views/admin/content_blocks/#{response[:model_name].underscore.gsub('_page', '')}.html.slim",
              '# ',
              before: "= #{find_page_field_type(row['B'])} f, :#{row['A']}"
            )
          # comment out this row's field for regular object forms
          else
            thor_action(
              :inject_into_file,
              "app/views/admin/#{response[:model_name].underscore.pluralize}/_form.html.slim",
              '# ',
              before: "= #{find_object_field_type(row['B'])} f, :#{row['A']}"
            )
          end
        elsif row['E'] == 'Update'
          # Changes are tricky to automate since we could be changing form field names, validations, db column names or types, etc.
          # To start lets inject a "TODO" note on the model to callout needed changes
          thor_action(
            :inject_into_file,
            "app/models/#{response[:model_name].underscore}.rb",
            "# TODO: CMS spec changes for row:\n# #{row}\n",
            before: "class #{response[:model_name]}"
          )
        else
          # No changes to this row. It already exists in the app, so just skip it
          next
        end

      end

    end
    return response
  end

  def delete_object(sheet)
    response = {
      script_args: [],
      model_name: nil,
      fae_generator_type: nil,
      parent_class: nil
    }
    sheet.simple_rows.each_with_index do |row, index|
      response[:model_name] = row['B'] if index == 0
      response[:fae_generator_type] = row['B'] if index == 8
    end
    # Disable admin route for this object
    thor_action(
      :inject_into_file,
      'config/routes.rb', '# ',
      before: "resources #{response[:model_name]}.underscore.pluralize"
    )
    # Add a note to remove admin navigation related to the object.
    thor_action(
      :inject_into_file,
      'app/models/concerns/fae/navigation_concern.rb',
      "\tTODO: disable nav for #{response[:model_name]}\n",
      after: "def structure\n"
    )

    # Optional if you want to fully destroy the model:
    # > Create a migration to remove the object table
    # sh "rails g migration Remove#{response[:model_name]}"
    # > Remove the model, fae views, and controllers
    # sh "rails destroy fae:#{response[:fae_generator_type]} #{response[:model_name]}"
  end

  def find_page_field_type(column_b)
    case column_b
    when 'image'
      'fae_image_form'
    when 'file'
      'fae_file_form'
    else
      'fae_content_form'
    end
  end

  def find_object_field_type(column_b)
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
