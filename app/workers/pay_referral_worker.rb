class PayReferralWorker
  include Sidekiq::Worker
  sidekiq_options retry: false

  def perform(first_stripe_account, second_stripe_account)
    Stripe::Transfer.create(
        {
          amount: (100 * ENV["REFER_BONUS"].to_r).to_i,
          currency: "usd",
          destination: first_stripe_account
        }
      )

      Stripe::Transfer.create(
        {
          amount: (100 * ENV["REFER_BONUS"].to_r).to_i,
          currency: "usd",
          destination: second_stripe_account
        }
      )
  end
end
