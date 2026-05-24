class ShareAuditLogsController < ApplicationController
  def index
    @audit_logs = ShareAuditLog.recent.limit(250)
  end
end
