class UsersController < ApplicationController
    
    def index
        unless params[:search] && params[:search] != ""
            @users = User.where.not(admin: true).order(:id)
        else
            @users = User.where('admin != (?) and lower(first_name) like (?) or lower(last_name) like (?) or lower(phone_number) like (?)', true, params[:search].downcase, params[:search].downcase, params[:search].downcase).order(:id)
        end
        authorize @users
    end
    
    def impersonate
        user = User.find(params[:id])
        impersonate_user(user)
        redirect_to root_path
    end
    
    def stop_impersonating
        stop_impersonating_user
        redirect_to root_path
    end

    def invite
        emails = params[:emails].split("\r\n")
        UserMailer.invite(emails).deliver
        flash[:success] = "Invites sent"
        redirect_back(fallback_location: root_path)
    end
end
