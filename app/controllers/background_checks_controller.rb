class BackgroundChecksController < ApplicationController
    skip_before_action :verify_authenticity_token
    before_action :authenticate_user!
    skip_before_action :is_active?

    before_action :go_to_dashboard    
    # before_action :go_to_payment, only: :pending
    # before_action :go_to_pending, only: :payment

    def payment
  
    end
  
    def pending
  
    end
  
    def charge
      Stripe.api_key = ENV['SECRET_KEY']
  
      token = params[:stripeToken]
      
      begin
        charge = Stripe::Charge.create({
          amount: !current_user.bgc_paid ? (100 * ENV["BGC_FEE"].to_r).to_i : (100 * ENV["MVR_FEE"].to_r).to_i,
          currency: 'usd',
          source: token,
          description: "Background check for #{current_user.email}"
        })
  
        BackgroundCheckWorker.perform_async(current_user.id)
        current_user.update_attributes(bgc_paid: true)
        zapier_webhook
        redirect_to bgc_pending_path
        
      rescue Stripe::StripeError => e
        flash[:error] = e.message
        redirect_to bgc_payment_path
      rescue => e
        flash[:error] = e.message
        redirect_to bgc_payment_path
      end
    end

    private
    def zapier_webhook
      unless ENV["POST_BGC_PAYMENT_WEBHOOK_URL"].blank?
        json_account = current_user.to_json
        options = { 
          :body => json_account
        }
    
        HTTParty.post(ENV["POST_BGC_PAYMENT_WEBHOOK_URL"], options)
      end
    end

    def go_to_dashboard
        redirect_to dashboard_path if current_user.is_active? && current_user.bgc_completed && current_user.bgc_completed + 6.months > Date.current + 14.days
    end

    def go_to_payment
        redirect_to bgc_payment_path unless current_user.bgc_paid
    end

    def go_to_pending
        redirect_to bgc_pending_path if current_user.bgc_paid
    end
end
