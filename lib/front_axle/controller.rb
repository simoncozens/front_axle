module FrontAxle
module Controller
  def self.included(base)
    base.extend(ClassMethods)
  end

  module ClassMethods
    def will_search(meth_names, options = {})
      if !meth_names.is_a? Array
        meth_names = [ meth_names]
      end
      meth_names.each do |meth_name|
        send(:define_method, meth_name.to_s) do
          _a_searcher(options)
        end
      end
    end
  end

  def _a_searcher(options)

    # Tidy search parameters
    if params[:q].instance_of? String # Mashed by the pager
       params.delete :q
    end
    if params[:q]
        params[:q].delete_if {|k,v| !v.present? or (v.instance_of?(Array) and v.select {|f| f.present?}.count ==0)  }
        params[:q].each {|k,v| v.uniq! if v.instance_of?(Array) }
    end

    @search = Search.build(model_class, params)
    klass = model_class.constantize
    @display_columns = klass::DISPLAY_COLUMNS.dup

    if options[:prepare]
        @display_columns = instance_exec(@display_columns,&options[:prepare])
    end
    options[:result_processor] ||= Proc.new {|x| x }

    if klass.const_defined? "YOU_MAY_ALSO_DISPLAY"
      klass::YOU_MAY_ALSO_DISPLAY.each do |x|
        if params[:q].key?(x[:column]) or params[:q].key?("min"+x[:column]) and @display_columns.select {|c| c[:column] == x[:column] }.count == 0
          @display_columns.push x.dup
        end
      end
    end

    if !params[:q].key?("did_search")
      params[:sort] ||= "updated_at_desc" #options[:default_sort_column]
      @display_columns.shift
    end
    respond_to do |format|
      format.html {
        page = params[:page].to_i
        if page < 1
          page = 1
        end
        @results = klass.search(params[:q], page, params[:sort])
        klass.search(params[:q], -1, params[:sort]).each do |p|
          instance_exec(p,&options[:result_processor])
        end
        render :index, :template => "layouts/search"
      }
      format.json {
        if params[:bounds]
          coords = params[:bounds].split (/,/)
          params[:q]["bounding_box"] = {
            :top_left => [ coords[1].to_f, coords[0].to_f ],
            :bottom_right => [ coords[3].to_f, coords[2].to_f ]
          }
        end
        @results = klass.search(params[:q], -1, params[:sort]).results.uniq {|r| r[:location] }
        # Dedupe the results
        @results = @results.map do |x|
          instance_exec(x,&options[:map_result_processor])
        end
        render :json => @results
      }
      format.csv {
        params[:q][:per] = 1000
        if current_user.role? "admin"
          params[:q][:per] = 2000
        end

        @results = klass.search(params[:q], 1, params[:sort])
        @csv_columns = []
        if klass.const_defined? "CSV_COLUMNS"
          @csv_columns = klass::CSV_COLUMNS.dup
        end
        if klass.const_defined? "YOU_MAY_ALSO_DISPLAY"
          @csv_columns.push(klass::YOU_MAY_ALSO_DISPLAY.dup).flatten!
        end
        if current_user.role? "admin"
          @csv_columns.unshift({:column => "id"})
          @csv_columns.push(klass::ADMIN_COLUMNS.dup).flatten! if klass.const_defined? "ADMIN_COLUMNS"
        end

        cols = @display_columns.select{|x| x[:column] != "relevance" } # Horrible special case
        if @csv_columns
          cols.push @csv_columns
        end
        _export_as_csv(@results, cols)
      }
    end
  end

  def _export_as_csv(results, cols)
    cols = cols.flatten.uniq_by { |c| c[:column] }
    header = cols.map{|c| c[:header] || c[:column].humanize }
    klass = model_class.constantize
    @filename = model_class.humanize+".csv"
    self.response.headers["Content-Type"] ||= 'text/csv'
    self.response.headers["Content-Disposition"] = "attachment; filename=#{@filename}"
    self.response.headers["Content-Transfer-Encoding"] = "binary"
    self.response.headers['Last-Modified'] = Time.now.to_s

    self.response_body = Enumerator.new do |y|
      results.each_with_index do |result, i|
        if i==0
          y << header.to_csv
        end
        line = []
        cols.each do |c|
          if c[:csvcode]
            col_data = c[:csvcode].call(result,view_context)
          elsif c[:code]
            col_data = c[:code].call(result,view_context)
          elsif result[c[:column]]
            col_data = result[c[:column]]
          end
          if col_data.class == Array
            col_data = col_data.join(" // ")
          end
          line.push col_data
        end
        y << line.to_csv
        GC.start if i%500==0
      end
    end
  end

  def build_report
    klass = model_class.constantize
    @cols = klass.columns.map {|c| c.name.to_sym }
    @assocs = klass.reflect_on_all_associations
    through={} ; @assocs.each {|x| through[x.options[:through]] =1 }
    @assocs = @assocs.select {|x| !through[x.name] }
    @tire_saved = klass.tire.mapping.keys
  end

  # I'm annoyed that there's so much repetition between this method and the _export_as_csv method,
  # but this is a more complex version of the standard CSV download. I wonder if there's a good way
  # to redefine that in terms of this one?
  def csv_report
    tire_cols = params[:tire] || {}
    ar_cols = params[:activerecord] || {}
    assocs_to_include = params[:assoc][:include] || {}
    params[:assoc][:max] ||= {}
    klass = model_class.constantize
    @filename = model_class.humanize+".csv"
    self.response.headers["Content-Type"] ||= 'text/plain'
    self.response.headers["Content-Disposition"] = "attachment; filename=#{@filename}"
    self.response.headers["Content-Transfer-Encoding"] = "binary"
    self.response.headers['Last-Modified'] = Time.now.to_s

    # Right, try to define a header:
    header = []
    tire_cols.keys.each { |x| header.push(x.humanize) }
    ar_cols.keys.each { |x| header.push(x.humanize) }
    assocs_to_include.keys.each do |assoc|
      if params[:assoc][:max][assoc] == "join" # Is a has_many with only one real column
        header.push params[:assoc][assoc.to_sym].keys.first
      elsif params[:assoc][:max][assoc] # has_many
        (1 .. (params[:assoc][:max][assoc].to_i)).each do |i|
          params[:assoc][assoc.to_sym].keys.each do |k|
            header.push( assoc.singularize.humanize+ " " + i.to_s + " " + k.humanize )
          end
        end
      else # has_a
        params[:assoc][assoc.to_sym].keys.each do |k| # Each key requested from the associated record
          header.push assoc.humanize+ " " + k.humanize
        end
      end
    end

    results = klass.search({per: TireSearch::INFINITY }, 1, "")
    self.response_body = Enumerator.new do |y|
      results.each_with_index  do |result, i|
        if i==0
          y << header.to_csv
        end
        line = []
        tire_cols.keys.each { |x| line.push(result[x]) }

        if ar_cols.count > 0 or assocs_to_include.keys.count > 0
          result = result.load
        end

        if ar_cols.count > 0
          ar_cols.keys.each {|x| line.push(result.send(x))}
        end
        assocs_to_include.keys.each do |assoc|
          related = result.send(assoc)
          if params[:assoc][:max][assoc] == "join" # Is a has_many with only one real column
            col = params[:assoc][assoc.to_sym].keys.first
            line.push related.map {|x| x.send(col)}.join(" // ")
          elsif params[:assoc][:max][assoc]
            (0 .. (params[:assoc][:max][assoc].to_i - 1)).each do |i|
              params[:assoc][assoc.to_sym].keys.each do |k|
                line.push( related[i] ? related[i].send(k) : nil)
              end
            end
          else
            params[:assoc][assoc.to_sym].keys.each do |k| # Each key requested from the associated record
              line.push related ? related.send(k) : nil
            end
          end
        end
        y << line.to_csv
        GC.start if i%500==0
      end
    end
  end
end
end
