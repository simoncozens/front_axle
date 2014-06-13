# FrontAxle

FrontAxle is a search engine for your Rails application. It uses the `tire`
interface to ElasticSearch to provide search, sorting and faceting of your
models.

## Setting up

* Install elasticsearch

* Add this to your model:

    class Project < ActiveRecord::Base
      include FrontAxle::Model

* Add this to your controller:

    class ProjectsController < ApplicationController
      include FrontAxle::Controller
      will_search([:index, :search])

* Add a `search` route to `routes.rb`:

    resources :projects do
      collection do
        match 'search' => 'projects#search', :via => [:get, :post], :as => :search
      end
    end

* Ensure that your `application_helper` defines `current_user`.

* Create a `Search` model and table in your database to save searches.

    rails g model Search parameters:string permanent:boolean name:string \
      target_model:string user:references

* Add some methods to your Search model

    def self.build(model, params)
      if params[:search_id]
        s = Search.find(params[:search_id])
        params[:q] = JSON.parse(s.parameters)
      else
        s = Search.where(:target_model => model, :parameters => params[:q].to_json, :user_id => User.current).first_or_create
      end
      if params[:searchname].present?
        s.permanent = 1
        s.name = params[:searchname]
      end
      s.update_attribute(:updated_at, Time.now)
      s.save
      return s
    end

    def to_description
      params = JSON.parse(parameters)
      # Return a user-facing description of the search here
    end

* Load each of your searchable models into the elasticsearch index: (see the tire documentation)

    Project.create_elasticsearch_index
    Project.import

* In your model, declare what columns you want to be in your results display:

    DISPLAY_COLUMNS = [
      { :column => "relevance", :ordering => "_score" },
      { :column => "id" },
      { :column => "name" }
    ]

* That should be it.

## Customizing

The above should get you a very basic search engine, but `front_axle` actually
provides a lot more functionality than just that.

### Better indexing

You will almost certainly want to customize the way that ElasticSearch indexes
your models. See the tire and ElasticSearch documentation for what column
types are available. You will certainly want to set up a mapping for your
index, and you will probably also want to set up a  `to_indexed_json` method
in your model to ensure that the data is handled the way you want.

    settings do
      mapping do
        indexes :id,         :index    => :not_analyzed
        indexes :name,       :analyzer => 'synsnowball', :boost => 100
        indexes :capacity,   :type => :float
        indexes :country,    :index => :not_analyzed
        indexes :start_date, :type => :date
        indexes :location,   :type => :geo_point
      end
    end

### Search columns

Just like the ElasticSearch mapping, most of the way that the search engine
operates is customized through declarations in the model file. The
`DISPLAY_COLUMNS` array sets which columns should appear in the result set.
Each column is specified as a hash with the following parameters:

* `:column`

The name of the attribute in the ElasticSearch index.

* `:header`

The user-visible name of this column as displayed in the results table.
(Defaults to the `.humanize`d name of the column)

* `:code`

Normally the search column simply displays the results of the attribute from
ElasticSearch. If you want to do something with the value, pass in a Proc to
`:code` instead. The Proc will receive two parameters: the result object from
tire, and a helper object. (allowing you to e.g. call `url_for` on it.) The
result of the Proc will be displayed instead.

For example:

    { :column => "price", 
      :code => lambda {|result,helper| helper.number_to_currency(result.price)} }

* `:link` and `:link_target`

Let's suppose you have a database of books, and you want a column which
represents the author (a `belongs_to` association). As well as displaying the
author, you want the `Author` column to link to the author's page.

If you index the `author` column,  you can create a link to view the author
by setting `:link` to true. 

This works, but it's ugly, because this normally requires a database hit to
look up the associated object, stringify it and so on. One of the ideals of
FrontAxle is that your search results should require only one call to
ElasticSearch and no database hits - that way your search is nice and speedy.

If you want to optimize your search to avoid database hits, you would instead
do this. First, declare your mapping to index both the author's name and their
database ID:

    mapping do
      ...
      indexes :author,    :as => "author.name"
      indexes :author_id, :index => :not_analyzed, :as => "author.id"
    end

Now the association lookup is done once, at indexing time. 

Next declare your author column like this:

    { :column => "author",
      :link_target => lambda {|result| { id: result.author_id, controller: "authors"} }
    }

The result of `:link_target` will be fed to `url_for` to construct the link.

### Facets

### Additional search columns

If a user searches for

### Customizing the display

### Mapping

## How a search request works
