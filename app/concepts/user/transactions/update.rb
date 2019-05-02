# frozen_string_literal: true

require 'dry/transaction'

module Sanchin
  module UserConcept
    module Transactions
      # Update a user from the database given its id.
      class Update
        include Dry::Transaction(container: Container)

        around :transaction, with: 'database.transaction'
        step  :find
        check :authorize
        check :match
        step  :validate
        step  :validate_credentials
        map   :hash
        step  :update

        private

        def find(input, id:)
          @user = User.where(id: id).for_update.first!
          Success input
        rescue
          Failure :not_found
        end

        def authorize(_input, _authenticated)
          true
        end

        def match(_input, last_seen)
          # NOTE: the updated_at dance is to trim the datetime at the second
          # granularity.
          updated_at = DateTime.iso8601(@user.updated_at.iso8601)
          !last_seen || updated_at <= last_seen
        end

        def validate(input)
          Schemas::Update.call(input).to_monad
        end

        def validate_credentials(validated)
          if validated[:password] && !validated[:login] && !@user.login
            Failure login: 'must be filled'
          elsif validated[:login] && !validated[:password] && !@user.password
            Failure password: 'must be filled'
          else
            Success validated
          end
        end

        def hash(validated)
          if validated[:password]
            cleartext = validated[:password]
            hashed = Container['password'].create cleartext
            validated[:password] = hashed
          end
          validated
        end

        def update(validated)
          @user.update(validated)
          Success @user.refresh
        rescue
          Failure login: 'is already taken'
        end
      end
    end
  end
end
