module FrontAxle
  module Model

    def self.included(base)
      base.extend(ClassMethods)
    end

    MAX_SIZE = 5000
    DEFAULT_SIZE = 20
    INFINITY = 500_000

    module ClassMethods
      def _search(params, page, order, query_block, facet_block, analyzer = 'synsnowball')
        klass = self
        page = 1 if page == 0 || !page
        Tire.configure { logger 'elasticsearch-rails.log' }

        tire.search do |s|
          qqq = lambda do |q|
            q.boolean do
              if params['query'].present?
                if analyzer.present?
                  must { match :_all, params['query'], { operator: 'AND', analyzer: analyzer } }
                else
                  must { match :_all, params['query'], operator: 'AND' }
                end
              else
                must { string '*' }
              end
              must { range :updated_at, from: params['updated_since'] } if params['updated_since'].present?
              if klass.const_defined? 'SLIDEY_FACETS'
                klass::SLIDEY_FACETS.select { |f| !f[:i_will_search] }.each do |f|
                  min = params["min#{f[:name]}"]
                  max = params["max#{f[:name]}"]
                  if min.present? && max.present?
                    if f[:type] == 'money'
                      max = max.to_f * 1_000_000
                      min = min.to_f * 1_000_000
                    end

                    must { range f[:name], from: min, to: max }
                  end
                end
              end
              if klass.const_defined? 'DATE_FACETS'
                klass::DATE_FACETS.each do |f|
                  min = params["min#{f}"]
                  max = params["max#{f}"]

                  must { range f.to_s, from: min, to: max } if min.present? && max.present?
                end
              end
              # TODO: initialize these constants as empty instead of dropping checks everywhere.
              if klass.const_defined? 'STRING_FACETS'
                klass::STRING_FACETS.each do |t|
                  must { terms t.to_s, params[t.to_s] } if params[t.to_s].present?
                end
              end
            end
            query_block.call(q) if query_block
          end

          if params['bounding_box'].present?
            s.query do |q|
              q.filtered do
                filter :geo_bounding_box, location: params['bounding_box']
                query(&qqq)
              end
            end
          elsif params['location_lat'].present? && params['distance'].present?
            s.query do |q|
              q.filtered do

                filter :geo_distance, distance: params['distance'], distance_type: 'plane',
                                      location: [params['location_lng'], params['location_lat']]
                query(&qqq)
              end
            end
          else
            s.query(&qqq)
          end

          facet_block.call(s) if facet_block

          if klass.const_defined? 'STRING_FACETS'
            klass::STRING_FACETS.each do |facet|
              t = Array(facet)[0]
              size = Array(facet)[1] || 1000
              s.facet(t.to_s) { terms t.to_s, size: size }
            end
          end

          if klass.const_defined? 'SLIDEY_FACETS'
            klass::SLIDEY_FACETS.select { |f| !f[:i_will_facet] }.each do |f|
              s.facet(f[:name].to_s) { histogram f[:name], interval: f[:interval] }
            end
          end

          if klass.const_defined? 'DATE_FACETS'
            klass::DATE_FACETS.each do |t|
              s.facet(t[:name].to_s) { date t[:name], interval: t.fetch(:interval) { 'month' } }
            end
          end

          search_size = params[:per] || DEFAULT_SIZE

          if order.present?
            desc = order.match(/_desc$/)
            key = order.gsub(/_desc$/, '')
            s.sort do
              by((klass.mapping.key?(("sort_#{key}").to_sym) ? "sort_#{key}" : key), desc ? 'desc' : ())
              by '_score'
            end
          end
          if page > 0
            s.from((page - 1) * search_size)
            s.size search_size
          else
            s.size MAX_SIZE
          end
        end
      end
    end
  end
end
