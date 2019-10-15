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
          # generate a migration to remove the field from the db and from CMS form
        elsif row['E'] == 'Update'
          # TDB
        else
          # No changes to this row, so just skip it
          next
        end

      end

    end
    return response
  end

end
