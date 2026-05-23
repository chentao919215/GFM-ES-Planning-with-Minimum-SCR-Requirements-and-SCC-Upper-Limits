function send_optional_completion_mail(subject, content)
%SEND_OPTIONAL_COMPLETION_MAIL 若项目中存在邮件函数，则发送完成提醒。

if exist('mailTome', 'file') == 2
    mailTome(subject, content);
end

end
