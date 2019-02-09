class UsersController < ApplicationController
    def index
        @users = User.where.not(admin: true).order(:id)
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
end
