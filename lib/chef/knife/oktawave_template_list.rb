require 'chef/knife/oktawave_base'

class Chef
  class Knife
    class OktawaveTemplateList < Knife
      include OktawaveBase
      banner 'knife oktawave template list (options)'
      def flush
        if @tem.length == 0
          return
        end
        puts "\n#{ui.color('Category', :bold)}: #{@cat.map {|c| api.dive2name(c, :template_category_name)[:category_name]}.join(' -> ')}"
        columns = api.dive2arr(@cat[@cat.length - 1], [:category_columns, :template_category_column]).map {|c|
          [api.dive2name(c[:column_name_dict])[:item_name], api.dive2name(c[:column_name_dict])[:dictionary_item_id]]
        }.select {|c| c[0] != 'ID'}
        template_list = [
          ui.color('ID', :bold),
          ui.color('Name', :bold),
          ui.color('Minimum class', :bold)
        ] + columns.map {|c| ui.color(c[0], :bold)}
        @tem.each do |t|
          template_list << ui.color(t[:template_id], :bold)
          template_list << t[:name]
          template_list << api.dive2name(t[:min_class])[:item_name]
          col_map = Hash[api.dive2arr(t, [:template_parameters, :template_parameter]).map {|p| [p[:column_name_dict_id], p[:column_value]]}]
          for c in columns
            template_list << col_map[c[1]] || ''
          end
        end
        puts ui.list(template_list, :columns_across, 3 + columns.length)
        @tem = []
      end
      def run
        validate!
        @tem = []
        @cat = []
        api.templates_list(Proc.new do |type, depth, data|
          just = ''.ljust(2 * depth)
          case type
          when :end_category
            flush
            @cat.pop
          when :category
            @cat << data
          when :template
            @tem << data
          end
        end)
      end
    end
  end
end
