require 'spec-importer/version'
require 'spec-importer/railtie' if defined?(Rails)

module SpecImporter
  class << self

    def create_object(sheet)
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
        next if row['E'].eql? 'Skip'

        if index > 10
          break if row['A'].blank? || row['B'].blank?
          if row['B'].eql?('join')
            # generate join table model and migration
            join_models = row['A'].split.sort
            script_args[:joins] << self.generate_join(join_models)
          else
            optional_index = row['C'].eql?(true) ? ':index' : ''
            row_args = "#{row['A']}:#{row['B']}" << optional_index
            script_args[:fae] << row_args
          end
        else
          next
        end
      end
      return script_args
    end

    def update_object(sheet)
      script_args = []
      model_name = sheet.simple_rows.first['B']
      fae_generator_type = sheet.simple_rows.to_a[8]['B']
      parent_class = sheet.simple_rows.to_a[8]['D']

      sheet.simple_rows.each_with_index do |row, index|
        next if row['E'].eql?('Skip')
        if index > 10 && (row['A'].blank? || row['B'].blank?)
          puts "Nothing to read in column A or B. Exiting the importer."
          break
        end

        if index > 10
          if row['E'].eql?('Add')
            if row['B'].eql?('join')
              # generate join table model and migration
              join_models = row['A'].split.sort
              self.generate_join(join_models)
            else
              puts "Adding new field: #{row['A']}:#{row['B']}"
              script_args << "#{row['A']}:#{row['B']}"
            end
          elsif row['E'].eql?('Remove')
            puts "Removing field: #{row['A']}:#{row['B']}"
            # generate a migration to remove the current row's column from the db
            sh "rails g migration Remove#{row['A'].classify}From#{model_name} #{row['A']}:#{row['B']}"

            # comment out this row's field for static page forms
            if fae_generator_type.eql?('Fae::StaticPage')
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
          elsif row['E'].eql?('Update')
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

    def remove_objects(sheet)
      sheet.simple_rows.each_with_index do |row, index|
        next if index < 2 || row['C'] != true
        model_name = row['A']
        break if index > 1 && model_name.blank?

        STDOUT.puts "Trying to remove #{model_name}\n"
        # Disable the admin route for this object
        begin
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
          # comment out the model and controller code for this model
          thor_action(:comment_lines, "app/models/#{model_name.underscore}.rb", /./)

          # if it's a Fae::StaticPage clean up the content blocks controller
          if index > 27
            thor_action(
              :gsub_file,
              "app/controllers/admin/content_blocks_controller.rb", /#{model_name}, /, ''
            )
          # otherwise try to comment out the admin controller (controllers may not exist for join models)
          else
            thor_action(:comment_lines, "app/controllers/admin/#{model_name.underscore.pluralize}_controller.rb", /./)
            thor_action(:comment_lines, "config/initializers/judge.rb", /expose #{model_name}, :slug/)
          end
        rescue Exception => e
          Rails.logger.warn e
        end

        # Optional: Destroy the model instead of just disabling/hiding
        # > Create a migration to remove the object table
        # sh "rails g migration Remove#{response[:model_name]}"
        # > Remove the model, fae views, and controllers
        # sh "rails destroy fae:#{response[:fae_generator_type]} #{response[:model_name]}"
      end
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

    def generate_join(models)
      "rails g model #{models.first.classify}#{models.second.classify} #{models.first}:references:index #{models.second}:references:index"
    end

    def associate_joined(models)
      join_model_name = "#{models.first}_#{models.second.pluralize}"
      model_a = models.first
      model_b = models.second

      thor_action(
        :inject_into_file,
        "app/models/#{model_a.underscore}.rb",
        "  has_many :#{join_model_name}\n  has_many :#{model_b.pluralize}, through: :#{join_model_name}\n",
        after: "class #{model_a.classify} < ApplicationRecord\n"
      )

      thor_action(
        :inject_into_file,
        "app/models/#{model_b.underscore}.rb",
        "  has_many :#{join_model_name}\n  has_many :#{model_a.pluralize}, through: :#{join_model_name}\n",
        after: "class #{model_b.classify} < ApplicationRecord\n"
      )
    end

    def add_nested_form_table(parent_model, nested_model)
      if parent_model.eql?('Fae::StaticPage')
        parent_form_path = "app/views/admin/content_blocks/#{parent_model.underscore}.html.slim"
        parent_item_str = "Fae::StaticPage.find_by_id(@item.id)"
        # add the has many association to the static page concern
        thor_action(
          :inject_into_file,
          "app/models/concerns/fae/static_page_concern.rb",
          "  has_many :#{nested_model.underscore.pluralize}, foreign_key: 'static_page_id'",
          after: "included do\n"
        )
      else
        # parent is_a? Object
        parent_form_path = "app/views/admin/#{parent_model.underscore.pluralize}/_form.html.slim"
        parent_item_str = "@item"
        # add the has many association to the parent model
        thor_action(
          :inject_into_file,
          "app/models/#{parent_model.underscore}.rb",
          "  has_many :#{nested_model.underscore.pluralize}\n",
          after: "class #{parent_model} < ApplicationRecord\n"
        )
      end
      nested_form_path = "app/views/admin/#{nested_model.underscore.pluralize}/table.html.slim"
      nested_form_string = %(
section.content\n
  / TODO: set col values to match settings on #{nested_model.underscore.pluralize}/table.html.slim
  == render 'fae/shared/nested_table',
    assoc: :#{nested_model.underscore.pluralize},
    parent_item: #{parent_item_str},
    cols: [:on_stage, :on_prod],
    ordered: true
)
      thor_action(
        :append_to_file,
        parent_form_path,
        nested_form_string
      )
    end

    def update_form_fields(sheet)
      # Read and import field labels and helper text for an object that has been generated.
      model = sheet.simple_rows.first['B']
      parent_model = sheet.simple_rows.to_a[8]['D']
      fae_generator_type = sheet.simple_rows.to_a[8]['B']

      sheet.simple_rows.each_with_index do |row, index|
        # ignore rows index 0 to 10 and if a row is marked skip, go to the next row.
        next if index < 11 || row['E'].eql?('Skip')

        # Exit the import if no field name is present.
        if row['F'].blank?
          STDOUT.puts "No form label/type specified in column F or G. Exiting the update_form_fields task."
          break
        end
        if fae_generator_type.eql?('page')
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

        # add a new form field for the join association and add the has_many through associations
        if row['B'].eql?('join')
          join_models = row['A'].split.sort
          joined_model = join_models.without(model.underscore).first

          thor_action(
            :inject_into_file,
            form_path,
            "\s\s\s\s= fae_multiselect f, :#{joined_model.pluralize}\n",
            after: "main.content\n"
          )
          self.associate_joined(join_models)
        end

        if row['B'].eql?('image')
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
        if row['H'].eql?(true) && fae_generator_type != 'page'
          thor_action(
            :inject_into_file,
            "app/models/#{model.underscore}.rb",
            "\tvalidates_presence_of :#{row['A']}\n",
            after: "include Fae::BaseModelConcern\n"
          )
        end

        # if markdown is true, add it to the form
        if row['I'].eql?(true)
          thor_action(
            :gsub_file,
            form_path,
            /f, :#{row['A']}\b/, "f, :#{row['A']}, markdown: true"
          )
        end
      end
      # For nested scaffold objects, we will want their nested table on their parent's form
      if fae_generator_type.eql?('nested_scaffold')
        self.add_nested_form_table(parent_model, model)
      end
    end

  end # class << self
end # module
