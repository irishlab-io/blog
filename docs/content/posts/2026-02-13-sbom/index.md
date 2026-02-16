---
title: "Dr. Strangelove or: How I Learned to Stop Worrying and Love the SBOM"
date: 2026-02-13
draft: false
description: "A comprehensive guide to integrating Syft and Grype in your CI/CD pipeline to generate immutable SBOMs and upload them to your self-hosted OWASP Dependency Track instance"
summary: "Learn how to leverage Syft for SBOM generation and Grype for vulnerability scanning, while integrating with OWASP Dependency Track for comprehensive supply chain security in your CI/CD pipeline"
tags: ["security", "sbom", "devsecops", "ci-cd", "grype", "syft", "dependency-track", "owasp"]
---

Software Bill of Materials (SBOM) has become a critical component of modern software supply chain security. With increasing regulatory requirements and security concerns, organizations need to maintain accurate inventories of their software components. In this post, I'll walk you through integrating Syft and Grype into your CI/CD pipeline to generate immutable SBOMs and upload them to a secure long-term storage location.

## Why SBOM Matters

An SBOM is essentially an inventory of all components, libraries, and dependencies used in your software. Think of it as a "ingredients list" for your application. Key benefits include:

- **Vulnerability Management**: Quickly identify which applications are affected when new vulnerabilities are discovered
- **License Compliance**: Track open source licenses across your organization
- **Supply Chain Security**: Understand your software's dependency tree
- **Regulatory Compliance**: Meet requirements like US Executive Order 14028, Canadian Bill C-26, and many industry standards and best practices

The primary SBOM formats, recognized for ensuring software supply chain security and interoperability, are [CycloneDX](https://cyclonedx.org/), [SPDX](https://spdx.dev/), and [SWID Tags](https://csrc.nist.gov/projects/Software-Identification-SWID). These formats enable automated, machine-readable documentation of components, licenses, and vulnerabilities.

- **CycloneDX (OWASP)**: A lightweight, modern format designed specifically for application security, vulnerability tracking, and supply chain security. It is highly versatile, supporting software, services, and hardware, and is often used within DevOps build pipelines.  CycloneDX tends to be more focused on security, vulnerability management, and ease of use in CI/CD pipelines.
- **SPDX (Linux Foundation)**: An open international standard (ISO/IEC 5962:2021) that originated for tracking software licenses but has evolved to include detailed component tracking, copyright, and security metadata.  SPDX is often favored for detailed legal compliance and intellectual property management.
- SWID Tags (ISO/IEC 19770-2): These are not full, comprehensive SBOM documents like CycloneDX or SPDX, but rather tags that provide identity and version information for software components.

## The Toolchain

[Syft](https://github.com/anchore/syft) is a powerful CLI tool and library for generating SBOMs from container images and filesystems. It supports multiple formats.
[Grype](https://github.com/anchore/grype) is a vulnerability scanner that works hand-in-hand with Syft. It can scan container images, filesystems, and SBOMs to identify known vulnerabilities from multiple databases.

The quickest way to get up and running is to use Anchore's helper scripts.

```bash
curl -sSfL https://get.anchore.io/syft | sudo sh -s -- -b /usr/local/bin
curl -sSfL https://get.anchore.io/grype | sudo sh -s -- -b /usr/local/bin
syft version
grype version
```

**Syft:**

To explore SBOMs, we'll use an obsolete, aging container. Container binaries are typically the final artifact that modern workflows promote between environments. Running `syft scan docker.io/python:3.10.11-alpine3.18` will scan and generate the associated container SBOM in the terminal, which is useful but not necessarily convenient. Still, we can see some interesting metadata from this container.

```text
  ~ ❯ syft scan docker.io/python:3.10.11-alpine3.18
 ✔ Loaded image          index.docker.io/library/python:3.10.11-alpine3.18
 ✔ Parsed image          sha256:bee261a96575c66a0d892947a6d7803348f49aa8734bc4a0ecb1df96c34d8134
 ✔ Cataloged contents    b42d5a5a34e11c7014e0bbb647f2b6970b2047043f19de43ce0d787a87091eb1
   ├── ✔ Packages                        [56 packages]
   ├── ✔ Executables                     [144 executables]
   ├── ✔ File metadata                   [1,030 locations]
   └── ✔ File digests                    [1,030 files]
NAME                    VERSION           TYPE
.python-rundeps         20230511.234154   apk
Simple Launcher         1.1.0.14          binary  (+5 duplicates)
alpine-baselayout       3.4.3-r1          apk
alpine-baselayout-data  3.4.3-r1          apk
alpine-keys             2.4-r1            apk
apk-tools               2.14.0-r0         apk
busybox                 1.36.0-r9         apk
busybox-binsh           1.36.0-r9         apk
ca-certificates         20230506-r0       apk
ca-certificates-bundle  20230506-r0       apk
cli                     UNKNOWN           binary
cli-32                  UNKNOWN           binary
cli-64                  UNKNOWN           binary
and many more...
```

Generating a `sbom.json` is fun, but on its own it isn't that useful. Many compliance frameworks require some form of SBOM to be published as part of a software release, but that's only one of the many actionable outcomes. [Anchore](https://anchore.com/), the company behind Syft, also produces [Grype](https://github.com/anchore/grype), a vulnerability scanner. Essentially, it's a two-step process: 1) generate a `sbom.json`; 2) evaluate that `sbom.json` for vulnerabilities.

Let's inspect our `sbom.json` file for vulnerabilities using `grype sbom:sbom.json`. CycloneDX is my preferred SBOM format, but this depends on your objectives.

**Grype:**

```text
  ~ ❯ grype sbom:sbom.json
 ✔ Scanned for vulnerabilities     [119 vulnerability matches]
   ├── by severity: 11 critical, 33 high, 66 medium, 9 low, 0 negligible
   └── by status:   107 fixed, 12 not-fixed, 0 ignored
NAME           INSTALLED  FIXED IN                                TYPE    VULNERABILITY        SEVERITY  EPSS           RISK
libcrypto3     3.1.0-r4   3.1.1-r0                                apk     CVE-2023-2650        Medium    92.0% (99th)   52.9
libssl3        3.1.0-r4   3.1.1-r0                                apk     CVE-2023-2650        Medium    92.0% (99th)   52.9
python         3.10.11    3.6.16, 3.8.17, 3.9.17, 3.10.12, ...    binary  CVE-2007-4559        Medium    90.6% (99th)   60.2
libcrypto3     3.1.0-r4   3.1.7-r0                                apk     CVE-2024-6119        High      5.7% (90th)    4.3
and many more...
56 packages from EOL distro "alpine 3.18.0" - vulnerability data may be incomplete or outdated; consider upgrading to a supported version
```

In the initial portion of its results output, Grype summarizes information on the scanned artifact and provides an overview of known vulnerabilities. In the case of a scanned image, the output includes the image digest, a unique hash that can be used as an identifier. The overview includes the number of packages, files, and executables found in the artifact. Generally speaking, CVEs are detected against packages, but the number of executables can also give you an idea of the attack surface of the scanned image or filesystem.

Finally, this portion gives a count of the number of CVEs detected by severity and fixed status. Severity categorization sorts CVEs into four categories based on the [Common Vulnerability Scoring System (CVSS)](https://www.first.org/cvss/v4.0/user-guide). CVSS scores correspond to four categories:

```text
1. Critical (9.0-10.0)
2. High (7.0-8.9)
3. Medium (4.0-6.9)
4. Low (0.1-3.9)
```

Grype also counts the number of CVEs by fixed status. If a CVE is marked as fixed, it can be resolved by updating to a newer version of the package. Our output suggests that 107 packages have fixes available and can be remediated with updates. It also identified that the `alpine 3.18.0` distro is end-of-life and should be upgraded as a whole.

## CI Integration

Now we have learned to generate and evaluate Software Bills of Material, which is fun, but at scale this is tedious and of limited value if done manually. Even with an army of interns, the pace at which new vulnerabilities appear makes this impractical. Therefore, automation it is. Let's look at an example using GitHub Actions workflows to achieve this.

There are many ways to build a CI pipeline, but in a nutshell you want something like the following:

{{< github-content
    repo="irishlab-io/blog"
    path=".github/workflows/sbom.yml"
    lang="yaml" >}}

This simple workflow generates and evaluates a container image for vulnerabilities, providing the feedback loop that can be orchestrated into your CI pipeline. Typically, this feedback loop should be an ascending ladder where the closer the code gets to the `main|master` branch, the lower the severity cutoff becomes.

Finally, this workflow attaches the `sbom.json` as a build artifact, but it should really be uploaded to some form of medium- to long-term storage and follow a specific naming convention (don't end up with 10 million unorganized `sbom.json` files). In the near future, I will dive into various SBOM management options and share my favorite.

## Vulnerabilities Rotting

Software development is a never-ending game of catching up when it comes to keeping your software free of vulnerabilities. The target moves, and eventually even the most secure software stack starts to crack as time goes on. This is why you should keep your SBOM stored somewhere for medium- to long-term use. On a regular basis, you should rescan the entirety of your SBOM output for newer vulnerabilities.

Given that container sizes are not typically a problem (a few GB at most), it is much more convenient to scan a few kB `sbom.json` file than to pull all the required containers to scan. Furthermore, this regular scan is quick to perform, even as an organization scales to dozens of applications and more.

## Now what ?!?

Well, you can check that box regarding regulation and compliance: you are generating the required SBOM artifact and can provide it as needed. Also, and this is where the fun really starts, you can build internal processes within your team and organization to triage and remediate these vulnerabilities. There are many strategies to consider when it's time to triage and fix vulnerabilities.

**Vulnerabilities origin:**

Investigate where you are most vulnerable. Are the bulk of the vulnerabilities found in your SBOM related to aging libraries or a widespread issue tied to an obsolete framework? Are dev dependencies included in the final artifact shipped to production? Do you really need all of these libraries, or should you refactor sub-optimal code and find better-suited solutions?

**Find better base image:**

Containers are convenient to ship, but do you really need the whole of `debian-trixie` to run a small Django web application? Maybe you could move to smaller footprint options (`slim` or `alpine` distributions). Why not go `distroless` or invest in a **golden image** such as those offered by [ChainGuard](https://www.chainguard.dev/)? A better base image will reduce the vulnerability count (often close to zero), but if you don't have a fast DevOps culture you might not be able to leverage these quickly. If your release cycles are counted in weeks, then **golden images** are mostly less useful given the "vulnerability rotting" that occurs.

**Automate depenencies upgrade:**

Several tools exist to automate dependency upgrades using different mechanisms. The most common pattern involves PR-based automation where tools suggest a simple version bump "à la *n+1*". This can help but is not a catch-all solution, and there are flaws with this approach.

## Wrapping Up

In the end, generating a Software Bill of Material is fairly easy and straightforward. It should be part of your CI pipeline, and your team should automate processes around it to manage SBOMs for medium- to long-term use and run vulnerability scanners to find critical issues to address.

---

## Resources

- [CycloneDX Specification](https://cyclonedx.org/)
- [Grype Documentation](https://github.com/anchore/grype)
- [SPDX Specification](https://spdx.dev/)
- [Syft Documentation](https://github.com/anchore/syft)
