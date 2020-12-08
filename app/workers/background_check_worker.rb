require 'checkr'

class BackgroundCheckWorker
  include Sidekiq::Worker

  def perform(user_id)
    user = User.find(user_id)

    Checkr.api_key = ENV["CHECKR_SECRET"]

    candidate = Checkr::Candidate.create({
      :first_name => user.first_name,
      :last_name => user.last_name,
      :email => user.email,
      :phone => user.phone_number
    })

    Checkr::Invitation.create({
      :candidate_id => candidate.id,
      :package => !user.bgc_completed ? ENV["BGC_TYPE"] : "mvr_only"
    })

    user.update_attributes(candidate_id: candidate.id)
  end
end
