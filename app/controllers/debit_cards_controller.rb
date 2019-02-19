class DebitCardsController < ApplicationController
  before_action :authenticate_user!

  def new
  end

  def create
    # Redirect if no token is POSTed or the user doesn't have a Stripe account
    unless params[:stripeToken] && current_user.stripe_account
      redirect_to debit_cards_create_path and return
    end

    begin
      # Retrieve the account object for this user
      account = Stripe::Account.retrieve(current_user.stripe_account)

      # Create the bank account
      account.external_accounts.create(external_account: params[:stripeToken])
      account.save

      # Success, send on to the dashboard
      flash[:success] = "Your debit card has been added!"
      redirect_to dashboard_path

    # Handle exceptions from Stripe
    rescue Stripe::StripeError => e
      handle_error(e.message, 'new')

    # Handle any other exceptions
    rescue => e
      handle_error(e.message, 'new')
    end
  end

  def destroy
  end

  def transfer
    begin
      # Retrieve the account object for this user
      account = Stripe::Account.retrieve(current_user.stripe_account)

      params[:method] == "instant" ? method = "instant" : method = "standard"

      # Create an instant payout
      payout = Stripe::Payout.create(
        {
          amount: params[:amount],
          currency: "usd",
          method: method,
          destination: params[:destination]
        },
        { stripe_account: account.id }
      )

      unless method == "standard"
        # Take a 3% fee for the instant payout
        Stripe::Charge.create(
          amount: params[:fee],
          currency: "usd",
          source: account.id,
          description: "Payout fee for #{payout.id}"
        )
      end

      # Success, send on to the dashboard
      flash[:success] = "Your payout has been made!"
      current_user.payout_wait = Date.today + 3.days
      current_user.save
      redirect_to dashboard_path

    # Handle exceptions from Stripe
    rescue Stripe::StripeError => e
      flash[:error] = e.message
      redirect_to dashboard_path

    # Handle any other exceptions
    rescue => e
      flash[:error] = e.message
      redirect_to dashboard_path
    end
  end
end
