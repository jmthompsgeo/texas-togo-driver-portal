class Stat < ApplicationRecord
  belongs_to :user
  before_save :default_values

  after_update :reached_x_deliveries, if: :deliveries_changed?

  def reached_x_deliveries
    if user.referrer && deliveries_was < ENV["REFER_DELIVERIES"].to_i && deliveries >= ENV["REFER_DELIVERIES"].to_i
      PayReferralWorker.perform_async(self.user.stripe_account, self.user.referrer.stripe_account)
      self.user.update_attributes(refer_paid: true)
    end
  end

  def default_values
      self.deliveries ||= 0
      self.days_worked ||= 0
  end
end
