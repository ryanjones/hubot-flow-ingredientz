#   Automates aspects of mover.io's current Github workflow which leverages
#   Github's issue tags and commenting system. We previously used a :+1:
#   comment to approve pull requests, but doing so did not affect the state of
#   the the PR.
#
#   Included is a Github webhook handler that checks for comments containing
#   certain trigger words. Currently:
#
#     :+1:      The pull request is approved.
#     :wave:    There are changes required with the PR.
#     :bell:    Please review this pull request.
#     :rocket:  The pull request is deployable.
#
#   Hubot will automatically @mention github users in certain cases. If your
#   github login does not match your hipchat login, use the 'workflow
#   aliasuser' command to define a mapping.
#
# Dependencies:
#   "querystring": "*"
#   "githubot": "*"
#
# Configuration:
#   Environment Variables:
#
#   WORKFLOW_ROOM - ie. 108111_username@conf.hipchat.com - The channel where messages ("1203 has been approved by
#     Sparks") will be sent.
#   HUBOT_GITHUB_USER - User that will be used to authenticate against the Github api.
#   HUBOT_GITHUB_TOKEN - I forget.
#   HUBOT_GITHUB_ORG - e.g. mover-io
#   HUBOT_GITHUB_REPO - e.g. one,two,three
#   HUBOT_HIPCHAT_JID - Jabber id for the Hipchat bot
#   HUBOT_HIPCHAT_PASSWORD - Password for the Hipchat bot.
#
# Commands:
#   hubot workflow aliasuser <github> <hipchat> - Map a github login to a hipchat login.
#   hubot workflow help - Outputs some additional help instructions.
#
# Notes:
#   The general form of github's API payload can be found here:
#   https://github.com/github/github-services/tree/master/docs
#
# Author:
#   jacobstr@gmail.com
#
# What's up with this Docblock? http://tomdoc.org/
url = require 'url'
util = require 'util'
querystring = require 'querystring'

url_api_base = "https://api.github.com"

room = process.env.WORKFLOW_ROOM

module.exports = (robot) ->

  github = require('githubot')(robot)

  # Documentation command
  robot.respond /workflow help/, (msg) ->
    msg.send """
    Commands:
      workflow aliasuser <github> <hipchat> - Maps a github login to a hipchat login.

    Github Pull Request Comments:
      Commenting on a github pull request with the following special emoticons triggers
      custom behaviours:

      :bell: - Marks an issue as needsreview.
      :rocket: - Marks an issue as deployable.
      :+1: - Marks an issue as approved.
      :wave: - Marks an issue as changesrequired.

      If you see an `@null` instead of a username, you'll want to run the aliasuser command.
    """
  robot.router.post "/hubot/github-workflow", (req, res) ->
    query = querystring.parse(url.parse(req.url).query)
    data = req.body

    if typeof data == 'string'
      try
        payload = JSON.parse data.payload
      catch error
        console.log "Failed to parse json from Github: #{util.inspect data}"
    else
      payload = data

    if payload and payload.action?
      if payload.action is 'created' and payload.comment?
        issue_comment github, robot, payload

    res.end ""

  # Allows us to map github logins to hipchat logins to map @mentions from
  # github pull requests.
  robot.respond /workflow aliasuser (\w*) (\w*)/, (msg) ->
    unless msg.match[1] and msg.match[2]
      msg.send "Please specify the github username followed by the hipchat username."
      return
    robot.brain.set "alias_#{msg.match[1]}", msg.match[2]
    msg.send "Cool. Mapping #{msg.match[1]} to #{msg.match[2]} when generating @mentions."

# See http://developer.github.com/webhooks/#events
#
# Each of the functions below corresponds to a github event type.
#
# The issue modification is documented here:
# http://developer.github.com/v3/issues/#edit-an-issue
#
# The general form of the url is:
#   PATCH /repos/:owner/:repo/issues/:number
# ... which corresponds to the comment's pull_request_url
#
# Sample payloads are provided in the github_api folder. Enjoy.
# ^^^ Sorry that's in our private hubot repo - github has a pretty good
# ui for this, however.
issue_comment = (github, robot, payload) ->

  add_labels = (current, new_labels) ->
    current.concat new_labels

  remove_labels = (current, to_remove) ->
    current.filter (el) -> el not in to_remove

  # Use +1 to trigger 'approved'
  if payload.comment.body.match /:\+1/
    robot.messageRoom room, "Pull request approved by #{payload.sender.login}: #{payload.issue.html_url}"

    github.get payload.comment.issue_url, (pull_request) ->
      filtered_labels = remove_labels (label.name for label in pull_request.labels), ['needsreview', 'changesrequired']
      query =
        title: pull_request.title
        labels: add_labels filtered_labels, ['approved']

      # Borks if you don't include a cb.
      github.patch payload.comment.issue_url, query, (result) ->

  # Use wave to trigger 'changesrequired'
  if payload.comment.body.match /:wave:/
    github.get payload.comment.issue_url, (pull_request) ->
      username = robot.brain.get "alias_#{pull_request.user.login}" or pull_request.user.login

      robot.messageRoom room, "@#{username}, #{payload.sender.login} thinks [ #{pull_request.title} ] needs changes #{payload.issue.html_url}"
      filtered_labels = remove_labels (label.name for label in pull_request.labels), ['approved','needsreview', 'deployable']

      github.patch payload.comment.issue_url, {
        title: pull_request.title
        labels: add_labels filtered_labels, ['changesrequired']
      }, (result) ->

  # Use bell to trigger 'needsreview'
  if payload.comment.body.match /:bell:/
    github.get payload.comment.issue_url, (pull_request) ->
      username = robot.brain.get "alias_#{payload.sender.login}" or payload.sender.login

      robot.messageRoom room, "@here #{username} wants [ #{pull_request.title} ] reviewed #{payload.issue.html_url}"
      filtered_labels = remove_labels (label.name for label in pull_request.labels), ['approved','deployable']

      github.patch payload.comment.issue_url, {
        title: pull_request.title
        labels: add_labels filtered_labels, ['needsreview']
      }, (result) ->

  # Use rocket to trigger 'deployable'
  if payload.comment.body.match /:rocket:/
    github.get payload.comment.issue_url, (pull_request) ->
      username = robot.brain.get "alias_#{pull_request.user.login}" or pull_request.user.login

      robot.messageRoom room, "Pull request [ #{pull_request.title} ] is deployable #{payload.issue.html_url}"
      filtered_labels = remove_labels (label.name for label in pull_request.labels), ['needreview','changesrequired']

      github.patch payload.comment.issue_url, {
        title: pull_request.title
        labels: add_labels filtered_labels, ['deployable']
      }, (result) ->
