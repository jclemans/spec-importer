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
          # generate a migration to remove the current row's column from the db
          response[:script_args] <<  "rails g migration Remove#{row['A']}From#{response[:model_name]} #{row['A']}:#{row['B']}"
        elsif row['E'] == 'Update'
          # TDB - this one could be tricky to automate since we could be changing many different attributes
          # Maybe we could at least inject a "TODO" note into the code to callout needed changes
        else
          # No changes to this row. It already exists in the app, so just skip it
          next
        end

      end

    end
    return response
  end

  def update_object(sheet)
    # read rows and make changes as specified
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
    # un-generate the current object
    sh "rails g migration Remove#{response[:model_name]}"
    # remove the model, fae views, and controllers
    sh "rails destroy fae:#{response[:fae_generator_type]} #{response[:model_name]}"
  end

end
