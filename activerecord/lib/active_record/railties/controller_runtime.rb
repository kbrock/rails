# frozen_string_literal: true

require "active_support/core_ext/module/attr_internal"
require "active_record/log_subscriber"

module ActiveRecord
  module Railties # :nodoc:
    module ControllerRuntime #:nodoc:
      extend ActiveSupport::Concern

    # TODO Change this to private once we've dropped Ruby 2.2 support.
    # Workaround for Ruby 2.2 "private attribute?" warning.
    protected

      attr_internal :db_runtime
      attr_internal :db_count

    private

      def process_action(action, *args)
        # We also need to reset the runtime before each action
        # because of queries in middleware or in cases we are streaming
        # and it won't be cleaned up by the method below.
        ActiveRecord::LogSubscriber.reset_runtime
        super
      end

      def cleanup_view_runtime
        if logger && logger.info? && ActiveRecord::Base.connected?
          db_rt_before_render = ActiveRecord::LogSubscriber.reset_runtime
          db_count_rt_before_render = ActiveRecord::LogSubscriber.reset_count
          self.db_runtime = (db_runtime || 0) + db_rt_before_render
          self.db_count = (db_count || 0) + db_count_rt_before_render
          runtime = super
          db_rt_after_render = ActiveRecord::LogSubscriber.reset_runtime
          db_count_rt_after_render = ActiveRecord::LogSubscriber.reset_count
          self.db_runtime += db_rt_after_render
          self.db_count += db_count_rt_after_render
          runtime - db_rt_after_render
        else
          super
        end
      end

      def append_info_to_payload(payload)
        super
        if ActiveRecord::Base.connected?
          runtime = ActiveRecord::LogSubscriber.reset_runtime
          count = ActiveRecord::LogSubscriber.reset_count
          payload[:db_runtime] = (db_runtime || 0) + runtime
          payload[:db_count] = (db_count || 0) + count
        end
      end

      module ClassMethods # :nodoc:
        def log_process_action(payload)
          messages, db_runtime, db_count = super, payload[:db_runtime], payload[:db_count]
          messages << ("ActiveRecord: %d queries %.1fms" % [db_count, db_runtime.to_f]) if db_runtime
          messages
        end
      end
    end
  end
end
