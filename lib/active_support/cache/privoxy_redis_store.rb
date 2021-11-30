module ActiveSupport
  module Cache
    # Redis store with Privoxy checking.
    class PrivoxyRedisStore < RedisCacheStore
      def read(name, options = nil)
        ActiveRecord::Base.connection.execute("CHECK CACHE READ #{name}")
        super
      end
    end
  end
end

