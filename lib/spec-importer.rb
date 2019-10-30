require 'spec-importer/version'
require 'spec-importer/railtie' if defined?(Rails)

module SpecImporter
  def self.create_object(sheet)
    model_name = sheet.simple_rows.first['B']
    # Exit if the current model already was created.
    return if Object.const_defined?(model_name)

    fae_generator_type = sheet.simple_rows.to_a[8]['B']
    parent_class = sheet.simple_rows.to_a[8]['D']
    script_args = {
      fae: ["rails g fae:#{fae_generator_type} #{model_name}"],
      joins: []
    }

    sheet.simple_rows.each_with_index do |row, index|
      next if row['A'] == 'skip'

      if index > 10
        break if row['A'].blank? || row['B'].blank?
        if row['B'] == 'join'
          # generate join table model and migration
          join_models = row['A'].split.sort
          script_args[:joins] << self.generate_join(join_models)
        else
          optional_index = row['C'] == true ? ':index' : ''
          row_args = "#{row['A']}:#{row['B']}" << optional_index
          script_args[:fae] << row_args
        end
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
          if row['B'] == 'join'
            # generate join table model and migration
            join_models = row['A'].split.sort
            self.generate_join(join_models)
          else
            puts "Adding new field: #{row['A']}:#{row['B']}"
            script_args << "#{row['A']}:#{row['B']}"
          end
        elsif row['E'] == 'Remove'
          puts "Removing field: #{row['A']}:#{row['B']}"
          # generate a migration to remove the current row's column from the db
          sh "rails g migration Remove#{row['A'].classify}From#{model_name} #{row['A']}:#{row['B']}"

          # comment out this row's field for static page forms
          if fae_generator_type == 'Fae::StaticPage'
            thor_action(
              :comment_lines,
              "app/views/admin/content_blocks/#{model_name.underscore.gsub('_page', '')}.html.slim",
              /"= #{self.find_page_field_type(row['B'])} f, :#{row['A']}"/
            )
          # comment out this row's field for regular object forms
          else
            thor_action(
              :comment_lines,
              "app/views/admin/#{model_name.underscore.pluralize}/_form.html.slim",
              /"= #{self.find_object_field_type(row['B'])} f, :#{row['A']}"/
            )
          end
        elsif row['E'] == 'Update'
          # Changes are tricky to automate since we could be changing form field names, validations, db column names or types, etc.
          # To start lets inject a "TODO" note on the model to callout needed changes
          thor_action(
            :prepend_to_file,
            "app/models/#{model_name.underscore}.rb",
            "# TODO: Spec Changes for field '#{row['A']}', Notes: #{row['L']}\n"
          )
        else
          # No changes to this row, so just skip it.
          next
        end

      end

    end
  end

  def self.delete_object(sheet)
    model_name = sheet.simple_rows.first['B']
    fae_generator_type = sheet.simple_rows.to_a[8]['B']

    # Disable admin route for this object
    thor_action(
      :comment_lines,
      'config/routes.rb',
      /"resources :#{model_name.underscore.pluralize}"/
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

  def self.generate_join(models)
    "rails g model #{models.first.classify}#{models.second.classify} #{models.first}:references:index #{models.second}:references:index"
  end

  def self.update_form_fields(sheet)
    # Read and import field labels and helper text for an object that has been generated.
    model = sheet.simple_rows.first['B']
    fae_generator_type = sheet.simple_rows.to_a[8]['B']

    sheet.simple_rows.each_with_index do |row, index|
      next if index < 11
      if row['F'].blank?
        STDOUT.puts "No form label present in column F. Exiting the form/helper updater."
        break
      end
      if fae_generator_type == 'page'
        form_path = "app/views/admin/content_blocks/#{model.underscore.gsub('_page', '')}.html.slim"
      else
        form_path = "app/views/admin/#{model.underscore.pluralize}/_form.html.slim"
      end
      # add labels and helper_text for each form field
      thor_action(
        :gsub_file,
        form_path,
        /f, :#{row['A']}\b/, "f, :#{row['A']}, label: '#{row["F"]}', helper_text: '#{row["K"]}'"
      )

      # add a new form field for the join association.
      if row['B'] == 'join'
        thor_action(
          :inject_into_file,
          form_path,
          "\t\t= fae_multiselect f, :#{row['A'].split.join('_')} # optionally a fae_grouped_select field\n",
          after: "main.content\n"
        )
      end

      if row['B'] == 'image'
        required_string = row['H'] ? ", required: true, " : ''
        # add image form field details
        thor_action(
          :inject_into_file,
          form_path,
          "#{required_string}",
          after: "= fae_image_form f, :#{row['A']}"
        )
      end
      # if required is true, add presence validations to object model
      if row['H'] == true && fae_generator_type != 'page'
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
          :gsub_file,
          form_path,
          /f, :#{row['A']}\b/, "f, :#{row['A']}, markdown: true"
        )
      end
    end
  end

end
