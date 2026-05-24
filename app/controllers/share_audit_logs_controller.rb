class ShareAuditLogsController < ApplicationController
  def index
    @filter_params = filter_params
    @actions = ShareAuditLog.distinct.order(:action).pluck(:action)
    @admins = ShareAuditLog.distinct.order(:admin_email).pluck(:admin_email)
    @audit_logs = filtered_logs.recent.limit(250)

    respond_to do |format|
      format.html
      format.csv do
        send_data ShareAuditLog.to_csv(filtered_logs.recent),
          filename: "plex-audit-log-#{Time.zone.today}.csv",
          type: "text/csv"
      end
    end
  end

  private

  def filtered_logs
    logs = ShareAuditLog.all
    logs = logs.where(admin_email: @filter_params[:admin_email]) if @filter_params[:admin_email].present?
    logs = logs.where(action: @filter_params[:action_type]) if @filter_params[:action_type].present?
    logs = logs.where("created_at >= ?", Time.zone.parse(@filter_params[:from])) if @filter_params[:from].present?
    logs = logs.where("created_at < ?", Time.zone.parse(@filter_params[:to]).tomorrow) if @filter_params[:to].present?
    if @filter_params[:q].present?
      query = "%#{ActiveRecord::Base.sanitize_sql_like(@filter_params[:q].to_s.strip)}%"
      logs = logs.where("target_label ILIKE :query OR target_email ILIKE :query OR plex_user_id ILIKE :query", query: query)
    end
    logs
  rescue ArgumentError
    ShareAuditLog.none
  end

  def filter_params
    params.permit(:q, :admin_email, :action_type, :from, :to)
  end
end
