class ApplicationController < ActionController::Base
  if Rails.env.include? "checked"
    around_action :set_blockaid_params
  end

  def set_blockaid_params
    # The user ID is set in `spree_auth_devise`.
    # ActiveRecord::Base.connection.execute("SET @_STORE_URL_PATTERN = '%#{request.env['SERVER_NAME']}%'")
    ActiveRecord::Base.connection.execute("SET @_TOKEN = '#{cookies.signed[:token]}'")
    yield
  ensure
    ActiveRecord::Base.connection.execute("SET @TRACE = null")
  end
end
