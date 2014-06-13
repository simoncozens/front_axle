module FrontAxle
  module ApplicationHelper

  def search_headers (columns, search=nil, mailing=nil)
    out = "".html_safe
    sortcol = ""
    if !mailing && params && params[:sort]
      sortcol = params[:sort]
    end
    columns.each do |c|
      col = "".html_safe
      col += c[:html_header] || c[:header] || c[:column].humanize
      unless !search or (c.key? :ordering and !c[:ordering]) or mailing
        c[:ordering] ||= c[:column]
        if sortcol.match(c[:ordering]+"$")
          # Then we are sorted asc so link to sort-desc if we can
          col += link_to "", { :sort => c[:ordering]+"_desc", :search_id => search.id }, :class => "caret-up"
        else
          col += link_to "", { :sort => c[:ordering], :search_id => search.id }, :class => "caret"
        end
      end
      htmlclass = ""
      if c[:money]
        htmlclass += "money"
      end
      if c[:ordering] && sortcol.match(c[:ordering])
        htmlclass += " sorted-by"
      end
      out += content_tag :th, col, :class => htmlclass
    end
    return out.html_safe
  end

  def search_results(result, columns)
    out = "".html_safe
    columns.each do |c|
      col = "".html_safe
      if c[:code]
        col_data = c[:code].call(result,self)

      elsif result.respond_to? c[:column]
        col_data = result[c[:column]]
      else
        col_data = result.load
      end
      if col_data.class == Array
        col_data = content_tag("ul",col_data.map {|x| content_tag("li",x)}.join("").html_safe)
      end
      if c[:link_target]
        link_target = c[:link_target].call(result)
        link_target[:controller] ||= controller_name
        out += content_tag :td, col_data ? link_to(col_data, url_for( :controller => link_target[:controller], :action => "show", :id => link_target[:id], :only_path => false ) ) : ""
      elsif c[:link]
        link_target = col_data
        unless link_target.respond_to?(:persisted?)
          throw "UNNECESSARY LOAD on "+c[:column] unless Rails.env.production?
          link_target = result.load
        end
        out += content_tag :td, col_data ? link_to(col_data, polymorphic_url(link_target, :only_path => false)) : ""
      elsif c[:money]
        if col_data && !(col_data.is_a?(String) && col_data.match(/^\$/))
          col_data = number_to_currency col_data
        end
        out += content_tag :td, col_data, :class => "money"
      else
        out += content_tag :td, col_data
      end
    end
    return out.html_safe
  end

  def string_facet_for(f_name, results, params)
    out = "".html_safe
    param = params[:q][f_name.to_sym]
    results.facets[f_name]["terms"].each do |t|
      item = "".html_safe
      item += check_box_tag "q["+f_name+"][]", t["term"], param ? param.member?(t["term"]) : nil
      item += t["term"].present? ? t["term"].humanize.to_s.split.map(&:capitalize).join(' ') : "Not specified"
      item += " ("+t["count"].to_s+")"
      out += content_tag :div, item, :class => "facet-line"
    end
    return content_tag :div, out, :class => "facet-content"
  end

  def slidey_facet_for(facet, params)
    data = @results.facets[facet[:name]]

    if facet[:type] == 'time'
      data['entries'].each do |entry|
        entry['time'] = entry['key']
      end
    end

    if data["terms"]
      data = data["terms"].sort{|a,b| a["term"] <=> b["term"]}
    else
      data = data["entries"].sort{|a,b| a["key"] <=> b["key"]}
    end
    if data.length == 0
      return
    end

    width = facet[:width] || "4em"

    inputs = ["min","max"].map { |l|
      name = l+facet[:name]
      htmlclass = ""
      if !params[:q][name].present?
        htmlclass = "pseudo-disabled"
      end
      content_tag(:span, content_tag(:span,
      (facet[:type] == "money" ? "$" : "").html_safe +
        text_field_tag("q[#{name}]", params[:q][name], { :style => "width:"+width , :class => htmlclass } ) +
      (facet[:type] == "money" ? "m" : ""), :class => "controls"), :class => "control-group")
    }.join("-")

    return (inputs +
      tag( :br ) +
      content_tag(:div, nil, :id => facet[:name]+"-histogram", :class => "sparkline") +
      content_tag(:div, nil, :id => "slider-"+facet[:name]) +
      content_tag(:script, "$(function() { facetSlider(\"#{facet[:name]}\",#{data.to_json.html_safe},#{facet[:type]=="money" ? 0.1 : 1}, #{facet[:interval] || 0}) })".html_safe
        )
    ).html_safe
  end  
  def things
    controller.controller_name.humanize.downcase
  end

  def thing
    things.singularize
  end

  def model_class
    if controller_name == "static"
      return nil
    end
    controller.controller_name.camelize.classify.constantize
  end  
end
end
