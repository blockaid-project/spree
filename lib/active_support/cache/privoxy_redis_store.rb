module ActiveSupport
  module Cache
    # Redis store with Privoxy checking.
    class PrivoxyRedisStore < RedisCacheStore
      def read_entry(key, **options)
        # puts '!!!'
        # puts key
        # puts caller
        ActiveRecord::Base.connection.execute("CHECK CACHE READ #{key}")
        super
      end
    end
  end
end

