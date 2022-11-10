//! mastty - CLI client for mastodon
//! Copyright (C) 2022 spazzylemons
//!
//! This program is free software: you can redistribute it and/or modify
//! it under the terms of the GNU General Public License as published by
//! the Free Software Foundation, either version 3 of the License, or
//! (at your option) any later version.
//!
//! This program is distributed in the hope that it will be useful,
//! but WITHOUT ANY WARRANTY; without even the implied warranty of
//! MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//! GNU General Public License for more details.
//!
//! You should have received a copy of the GNU General Public License
//! along with this program.  If not, see <http://www.gnu.org/licenses/>.

const std = @import("std");

fn jsonFree(comptime T: type) type {
    return struct {
        pub fn deinit(self: T, allocator: std.mem.Allocator) void {
            std.json.parseFree(T, self, .{ .allocator = allocator });
        }
    };
}

pub const Account = struct {
    pub usingnamespace jsonFree(@This());

    id: []const u8,
    username: []const u8,
    acct: []const u8,
    url: []const u8,
    display_name: []const u8,
    note: []const u8,
    avatar: []const u8,
    avatar_static: []const u8,
    header: []const u8,
    header_static: []const u8,
    locked: bool,
    emojis: []Emoji,
    discoverable: bool,
    created_at: []const u8,
    last_status_at: []const u8,
    statuses_count: u64,
    followers_count: u64,
    following_count: u64,
    moved: ?*Account = null,
    fields: ?[]Field = null,
    bot: ?bool = null,
    source: ?Source = null,
    suspended: ?bool = null,
    mute_expires_at: ?[]const u8 = null,
};

pub const Application = struct {
    pub usingnamespace jsonFree(@This());

    name: []const u8,
    website: ?[]const u8 = null,
    vapid_key: ?[]const u8 = null,
    client_id: ?[]const u8 = null,
    client_secret: ?[]const u8 = null,
};

pub const Attachment = struct {
    pub usingnamespace jsonFree(@This());

    id: []const u8,
    type: enum {
        unknown,
        image,
        gifv,
        video,
        audio,
    },
    url: []const u8,
    preview_url: []const u8,
    remote_url: ?[]const u8 = null,
    // TODO - probably can't add meta field to serialization because it varies in structure?
    description: ?[]const u8 = null,
    blurhash: ?[]const u8 = null,
};

pub const Card = struct {
    pub usingnamespace jsonFree(@This());

    url: []const u8,
    title: []const u8,
    description: []const u8,
    type: enum {
        link,
        photo,
        video,
        rich,
    },
    author_name: ?[]const u8 = null,
    author_url: ?[]const u8 = null,
    provider_name: ?[]const u8 = null,
    provider_url: ?[]const u8 = null,
    html: ?[]const u8 = null,
    width: ?u64 = null,
    height: ?u64 = null,
    image: ?[]const u8 = null,
    embed_url: ?[]const u8 = null,
    blurhash: ?[]const u8 = null,
};

pub const Emoji = struct {
    pub usingnamespace jsonFree(@This());

    shortcode: []const u8,
    url: []const u8,
    static_url: []const u8,
    visible_in_picker: []const u8,
    category: ?[]const u8 = null,
};

pub const Field = struct {
    pub usingnamespace jsonFree(@This());

    name: []const u8,
    value: []const u8,
    verified_at: ?[]const u8 = null,
};

pub const History = struct {
    day: []const u8,
    uses: []const u8,
    accounts: []const u8,
};

pub const Mention = struct {
    pub usingnamespace jsonFree(@This());

    id: []const u8,
    username: []const u8,
    acct: []const u8,
    url: []const u8,
};

pub const Poll = struct {
    pub usingnamespace jsonFree(@This());

    id: []const u8,
    expires_at: ?[]const u8 = null,
    expired: bool,
    multiple: bool,
    votes_count: u64,
    voters_count: ?u64 = null,
    voted: ?bool = null,
    own_votes: ?[]u64 = null,
    options: []struct {
        title: []const u8,
        votes_count: ?u64 = null,
    },
    emojis: []Emoji,
};

pub const Source = struct {
    pub usingnamespace jsonFree(@This());

    note: []const u8,
    fields: []Field,
    privacy: ?Visibility = null,
    sensitive: ?bool = null,
    language: ?[]const u8 = null,
    follow_requests_count: ?u64 = null,
};

pub const Status = struct {
    pub usingnamespace jsonFree(@This());

    id: []const u8,
    uri: []const u8,
    created_at: []const u8,
    account: Account,
    content: []const u8,
    visibility: Visibility,
    sensitive: bool,
    spoiler_text: []const u8,
    media_attachments: []Attachment,
    application: ?Application = null,
    mentions: []Mention,
    tags: []Tag,
    emojis: []Emoji,

    reblogs_count: u64,
    favourites_count: u64,
    replies_count: u64,

    url: ?[]const u8 = null,
    in_reply_to_id: ?[]const u8 = null,
    in_reply_to_account_id: ?[]const u8 = null,
    reblog: ?*Status = null,
    poll: ?Poll = null,
    card: ?Card = null,
    language: ?[]const u8 = null,
    text: ?[]const u8 = null,
    favourited: bool,
    reblogged: bool,
    muted: bool,
    bookmarked: bool,
    pinned: ?bool = null,
};

pub const Tag = struct {
    pub usingnamespace jsonFree(@This());

    name: []const u8,
    url: []const u8,
    history: ?[]History = null,
};

pub const Token = struct {
    pub usingnamespace jsonFree(@This());

    access_token: []const u8,
    token_type: []const u8,
    scope: []const u8,
    created_at: i64,
};

pub const Visibility = enum {
    public,
    unlisted,
    private,
    direct,
};
