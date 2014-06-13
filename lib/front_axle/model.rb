module FrontAxle
module Model

  def self.included(base)
    base.extend(ClassMethods)
  end

	MAX_SIZE = 5000
	DEFAULT_SIZE = 20
	INFINITY = 500_000

	module ClassMethods

	def _search(params, page, order, query_block, facet_block, analyzer="synsnowball")
		klass = self
		page = 1 if page==0 or !page
		Tire.configure { logger "elasticsearch-rails.log" }
		tire.search do |s|
			qqq = lambda do |q|
				q.boolean do
					if params["query"].present?
						if analyzer.present?
							must { match :_all, params["query"], {:operator => "AND", :analyzer => analyzer} }
						else
							must { match :_all, params["query"], :operator => "AND" }
						end
					else
						must { string "*" }
					end
					must { range :updated_at, { :from => params["updated_since"] }} if params["updated_since"].present?
					if klass.const_defined? "SLIDEY_FACETS"
						klass::SLIDEY_FACETS.select{|f| !f[:i_will_search] }.each do |f|
							if params["min"+f[:name].to_s].present? and params["max"+f[:name].to_s].present?
								min = (params["min"+f[:name].to_s])
								max = (params["max"+f[:name].to_s])
								if f[:type] == "money"
									max = max.to_f * 1000000
									min = min.to_f * 1000000
								end
							must { range f[:name], :from => min, :to => max }
								end
						end
					end
					if klass.const_defined? "DATE_FACETS"
						klass::DATE_FACETS.each do |f|
							if params["min"+f.to_s].present? and params["max"+f.to_s].present?
							must { range f.to_s, :from => params["min"+f.to_s],
									:to => params["max"+f.to_s] }
								end
						end
					end
					if klass.const_defined? "STRING_FACETS"
						klass::STRING_FACETS.each do |t|
							must { terms t.to_s, params[t.to_s] } if params[t.to_s].present?
						end
					end
				end
				if query_block
	  			query_block.call(q)
		  	end
			end

			if params["bounding_box"].present?
				s.query do |q|
					q.filtered do
						filter :geo_bounding_box, :location => params["bounding_box"]
						query(&qqq)
					end
				end
			elsif params["location_lat"].present? and params["distance"].present?
				s.query do |q|
					q.filtered do
						filter :geo_distance, :distance => params["distance"], :distance_type => "plane", :location => [params["location_lng"], params["location_lat"]]
						query(&qqq)
					end
				end
			else
				s.query(&qqq)
			end

			if facet_block
				facet_block.call(s)
			end

			if klass.const_defined? "STRING_FACETS"
				klass::STRING_FACETS.each do |t|
					s.facet t.to_s do terms t.to_s end
				end
			end

			if klass.const_defined? "SLIDEY_FACETS"
				klass::SLIDEY_FACETS.select{|f| !f[:i_will_facet] }.each do |f|
					s.facet f[:name].to_s do histogram f[:name], :interval => f[:interval] end
				end
			end

			if klass.const_defined? "DATE_FACETS"
				klass::DATE_FACETS.each do |t|
					# TODO: we currently don't handle non-numeric intervals in the front end.
					s.facet t[:name].to_s do date t[:name], { interval: t.fetch(:interval) { 'month' } } end
				end
			end

			search_size = params[:per] || DEFAULT_SIZE

			if order.present?
				desc = order.match(/_desc$/)
				key = order.gsub(/_desc$/, "")
				s.sort { by((klass.mapping.key?(("sort_"+key).to_sym) ? "sort_"+key : key), desc ? "desc" : ())
					by "_score"
				}
			end
			if page > 0
				s.from (page -1) * search_size
				s.size search_size
			else
				s.size MAX_SIZE
			end
		end
	end
end
end
end
