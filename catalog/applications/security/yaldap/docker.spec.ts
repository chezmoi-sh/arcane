import { randomUUID } from "crypto";
import { getRandomPort } from "get-port-please";
import LdapClient from "ldapjs-client";
import tmp from "tmp";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";

import * as automation from "@pulumi/pulumi/automation";
import { FileAsset } from "@pulumi/pulumi/asset";

import { SecretAsset } from "@chezmoi.sh/core/utils";

import { AlpineImage, Version as AlpineVersion } from "../../../os/alpine/3.19";
import { Version, yaLDAP } from "./docker";

const isIntegration = (process.env.VITEST_RUN_TYPE ?? "").includes("integration:docker");
const timeout = 2 * 60 * 1000; // 2 minutes

const AlpineImageTag = `${process.env.CI_OCI_REGISTRY ?? "oci.local.chezmoi.sh"}/os/alpine:${AlpineVersion}`;
const yaLDAPImageTag = `${process.env.CI_OCI_REGISTRY ?? "oci.local.chezmoi.sh"}/security/yaldap:${Version}`;

describe.runIf(isIntegration)("(Security) yaLDAP", () => {
    describe("yaLDAP", () => {
        describe("when it is deployed", { timeout }, async () => {
            const ports = {
                ldap: await getRandomPort(),
            };

            // -- Prepare Pulumi execution --
            const program = async () => {
                const alpine = new AlpineImage(randomUUID(), { push: true, tags: [AlpineImageTag] });
                const yaldap = new yaLDAP(randomUUID(), {
                    configuration: new SecretAsset(new FileAsset(`${__dirname}/fixtures/backend.yaml`)),

                    imageArgs: { from: alpine, push: true, tags: [yaLDAPImageTag] },
                    containerArgs: {
                        ports: [{ internal: 389, external: ports.ldap, protocol: "tcp" }],
                        wait: true,
                    },
                });
                return { ...yaldap.container };
            };

            let stack: automation.Stack;
            let result: automation.UpResult;
            beforeAll(async () => {
                const tmpdir = tmp.dirSync();
                stack = await automation.LocalWorkspace.createOrSelectStack(
                    {
                        stackName: "yaldap",
                        projectName: "yaldap",
                        program,
                    },
                    {
                        secretsProvider: "passphrase",
                        projectSettings: {
                            name: "yaldap",
                            runtime: "nodejs",
                            backend: {
                                url: `file://${tmpdir.name}`,
                            },
                        },
                    },
                );
                result = await stack.up();
            }, timeout);

            beforeEach(() => {
                expect(result.summary.result, "should be successfully deployed").toBe("succeeded");
            });

            afterAll(async () => {
                await stack.destroy();
            }, timeout);

            // -- Assertions --
            it("should be able to resolve LDAP queries", { concurrent: true }, async () => {
                const client = new LdapClient({ url: `ldap://localhost:${ports.ldap}` });
                await client.bind("cn=alice,ou=people,c=fr,dc=example,dc=org", "alice");

                const entries = await client.search("dc=example,dc=org", { scope: "sub", filter: "(objectClass=*)" });
                expect(entries).toHaveLength(16);
            });
        });
    });
});
