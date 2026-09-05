import test from 'node:test';
import assert from 'node:assert/strict';
import { PermissionFlagsBits } from 'discord.js';
import { canRunServerAction } from '../plugins/commands.js';

const regularMemberPermissions = {
    has: () => false
};

const managerPermissions = {
    has: permission => permission === PermissionFlagsBits.ManageGuild
};

test('/server start is available to every guild member', () => {
    assert.equal(canRunServerAction('start', regularMemberPermissions), true);
    assert.equal(canRunServerAction('start', null), true);
});

test('/server status and stop still require Manage Server', () => {
    assert.equal(canRunServerAction('status', regularMemberPermissions), false);
    assert.equal(canRunServerAction('stop', regularMemberPermissions), false);
    assert.equal(canRunServerAction('status', managerPermissions), true);
    assert.equal(canRunServerAction('stop', managerPermissions), true);
});
