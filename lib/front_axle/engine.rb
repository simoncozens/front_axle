module FrontAxle
  class Engine < ::Rails::Engine

    config.to_prepare do
      ApplicationController.helper(FrontAxle::ApplicationHelper)
    end

  end
end
