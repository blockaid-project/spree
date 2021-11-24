class ApplicationController < ActionController::Base
  before_action :set_blockaid_params

  def set_blockaid_params
    ActiveRecord::Base.connection.execute("SET @TRACE = null")
    ActiveRecord::Base.connection.execute("SET @_STORE_URL_PATTERN = '%#{request.env['SERVER_NAME']}%'")
  end
end
