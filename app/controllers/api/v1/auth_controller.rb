module Api
  module V1
    class AuthController < ApplicationController
      # POST /api/v1/auth/wechat
      def wechat
        code = params[:code]
        return render json: { message: "code is required" }, status: :bad_request if code.blank?

        # TODO: replace with real WeChat API call:
        # GET https://api.weixin.qq.com/sns/jscode2session
        #   ?appid=APPID&secret=SECRET&js_code=CODE&grant_type=authorization_code
        # → { openid, session_key }
        openid = "mock_#{code[0, 12]}"

        User.find_or_create_by!(openid: openid)

        render json: { openid: openid }
      end
    end
  end
end
