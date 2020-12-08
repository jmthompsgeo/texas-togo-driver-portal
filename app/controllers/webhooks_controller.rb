class WebhooksController < ApplicationController
  protect_from_forgery except: [:stripe, :checkr]
  before_action :verify_request, only: :checkr

  def checkr
    case params[:type]
    when 'report.completed'
      status = params[:data][:object][:status]
      if status === 'clear'
        activate_account
        zap_webhook_on_checkr_pass
      end
    when 'report.engaged'
      activate_account
      zap_webhook_on_checkr_pass
    when 'report.pre_adverse_action'
      activate_account(false)
    when 'report.post_adverse_action'
      lock_account
    end
  end

  def stripe
    # Use signed webhooks
    endpoint_secret = ENV['ENDPOINT_SECRET'].to_s

    payload = request.body.read
    sig_header = request.env['HTTP_STRIPE_SIGNATURE']
    event = nil

    begin
      event = Stripe::Webhook.construct_event(payload, sig_header, endpoint_secret)

      case event.type

      #############
      # Disputes
      #############

      # Recover dispute amounts and fees for disputed charges
      when 'charge.dispute.created'
        # The dispute that was created
        dispute = event.data.object

        # Retrieve the charge related to this dispute
        charge = Stripe::Charge.retrieve(dispute.charge)

        # Retrieve the platform account ID. You could also store this in an env variable.
        platform_account = Stripe::Account.retrieve

        # Issue a transfer reversal to recover the funds
        reverse_transfer(charge)

        # Create an account debit to recover dispute fee
        debit = Stripe::Transfer.create(
          {
            amount: dispute.balance_transactions.first.fee,
            currency: "usd",
            destination: platform_account.id,
            description: "Dispute fee for #{charge.id}"
          },
          { stripe_account: charge.destination }
        )

      # Return charge amount and fees if dispute is won
      when 'charge.dispute.funds_reinstated'
        # The dispute that was created
        dispute = event.data.object

        # Retrieve the charge related to this dispute
        charge = Stripe::Charge.retrieve(dispute.charge)

        # Create a transfer to the connected account to return the dispute fee
        transfer = Stripe::Transfer.create(
          amount: dispute.balance_transactions.second.net,
          currency: "usd",
          destination: charge.destination
        )

        # Retrieve the destination payment
        payment = Stripe::Charge.retrieve(
          {
            id: transfer.destination_payment
          },
          {
            stripe_account: transfer.destination
          }
        )

        # Update the description on the destination payment
        payment.description = "Chargeback reversal for #{charge.id}"
        payment.save

      when 'payout.failed'
        payout = event.data.object

        unless payout.method == "standard"
          orig_amt_cents = payout.amount/(1-ENV["INSTANT_PAYOUT_FEE"].to_f)
          (orig_amt_cents*ENV["INSTANT_PAYOUT_FEE"].to_f).round >= (100 * ENV["INSTANT_PAYOUT_MINIMUM"].to_r).to_i ? fee = (orig_amt_cents*ENV["INSTANT_PAYOUT_FEE"].to_f).round : fee = (100 * ENV["INSTANT_PAYOUT_MINIMUM"].to_r).to_i

          # Create a transfer to the connected account to return the dispute fee
          transfer = Stripe::Transfer.create(
            amount: fee,
            currency: "usd",
            destination: event.account
          )
          end
      end

    # Something bad happened with the event or retrieving details from Stripe: probably log this.
    rescue JSON::ParserError, Stripe::SignatureVerificationError, Stripe::StripeError => e
      head :bad_request

    # Handle other exceptions. You may want to log these for review later too.
    rescue => e
      head :bad_request
    end

    # Return a 200
    head :ok
  end

  private
    def verify_request
      digest = OpenSSL::Digest.new('sha256')
      hmac = OpenSSL::HMAC.hexdigest(digest, ENV['CHECKR_SECRET'], request.body.read)
      base64 = Base64.encode64(hmac)

      return head :unauthorized unless ActiveSupport::SecurityUtils.secure_compare(hmac, request.headers['X-Checkr-Signature'])
    end

    def activate_account(activate=true)
      user_by_candidate.update_attributes(is_active: activate, bgc_completed: (activate ? Date.current : nil)) if user_by_candidate
    end

    def zap_webhook_on_checkr_pass
      if user_by_candidate
        unless ENV["BGC_PASSED_WEBHOOK_URL"].blank?
          puts '%%%%%%%%%%%%%%%%%%'
          json_account = user_by_candidate.to_json
          options = { 
            :body => json_account
          }
      
          HTTParty.post(ENV["BGC_PASSED_WEBHOOK_URL"], options)
        end
      end
    end

    def lock_account
      user_by_candidate.lock_access! if user_by_candidate
    end

    def user_by_candidate
      User.find_by(candidate_id: params[:data][:object][:candidate_id])
    end

    def reverse_transfer(charge)
      # Retrieve the transfer for the charge
      transfer = Stripe::Transfer.retrieve(charge.transfer)

      # Reverse the transfer and keep the application fee
      transfer.reversals.create
    end
end
