# Data Processing Agreement (DPA)

**Effective Date: January 2, 2026**

**This is a template for informational purposes. Consult with a qualified attorney for legal advice specific to your situation.**

This Data Processing Agreement ("DPA") forms part of the Terms of Service between [YOUR COMPANY NAME] ("Processor", "we", "us") and the customer ("Controller", "you") for the use of CHOM - Cloud Hosting & Observability Manager ("Services").

This DPA complies with the General Data Protection Regulation (GDPR) EU 2016/679, UK GDPR, and incorporates Standard Contractual Clauses (SCCs) for international data transfers.

## 1. Definitions

**1.1** Terms used in this DPA have the meanings set out in the GDPR unless otherwise defined:

- **"Controller"**: The entity that determines the purposes and means of processing Personal Data (you, the customer)
- **"Processor"**: The entity that processes Personal Data on behalf of the Controller ([YOUR COMPANY NAME])
- **"Personal Data"**: Any information relating to an identified or identifiable natural person
- **"Processing"**: Any operation performed on Personal Data (collection, storage, use, disclosure, deletion)
- **"Data Subject"**: An identified or identifiable natural person whose Personal Data is processed
- **"Sub-processor"**: Any third-party processor engaged by the Processor
- **"Supervisory Authority"**: An independent public authority established by an EU Member State
- **"Data Protection Laws"**: GDPR, UK GDPR, and all applicable data protection legislation

## 2. Scope and Applicability

**2.1 Scope of DPA**
This DPA applies to all Processing of Personal Data by the Processor on behalf of the Controller in connection with the Services.

**2.2 Role of Parties**
- **Controller**: You are the data controller for any end-user Personal Data processed through the Services
- **Processor**: We are a data processor acting solely on your documented instructions
- **Your Personal Data**: For your organization's account data (user names, emails, billing), we may act as both controller and processor per our Privacy Policy

**2.3 Hierarchy of Documents**
In case of conflict, documents are interpreted in this order:
1. This Data Processing Agreement (DPA)
2. Standard Contractual Clauses (SCCs) - Annex A
3. Terms of Service
4. Privacy Policy

## 3. Processing of Personal Data

**3.1 Subject Matter of Processing**
Processing necessary to provide the CHOM platform services, including:
- Hosting WordPress, HTML, and Laravel sites
- VPS server management and provisioning
- Automated backup and restore operations
- User authentication and authorization
- Observability metrics and log aggregation

**3.2 Duration of Processing**
From the effective date of the Terms of Service until 30 days after termination (data retention period).

**3.3 Nature and Purpose of Processing**
- **Nature**: Storage, retrieval, organization, transmission, backup, and deletion of Personal Data
- **Purpose**: Providing cloud hosting, site management, and observability services per the Controller's instructions

**3.4 Types of Personal Data**
Personal Data processed may include:
- **Identification Data**: Names, usernames, email addresses
- **Technical Data**: IP addresses, browser information, device identifiers
- **Usage Data**: Site access logs, performance metrics, application logs
- **Communication Data**: Support tickets, email correspondence
- **Site Content**: Any Personal Data uploaded by Controller to hosted sites

**Note**: The specific Personal Data depends on what the Controller and its end-users upload.

**3.5 Categories of Data Subjects**
- Controller's employees and team members
- Controller's end-users (website visitors, customers)
- Controller's contractors and service providers
- Any individuals whose data Controller processes through the Services

**3.6 Special Categories of Personal Data**
- **Restriction**: Controller must NOT upload special category data (GDPR Article 9) without prior written agreement
- **Special Categories**: Racial/ethnic origin, political opinions, religious beliefs, genetic data, biometric data, health data, sex life/sexual orientation
- **Exception**: If Controller requires processing special categories, contact legal@[YOUR-DOMAIN].com for addendum

## 4. Controller's Instructions

**4.1 Processing Instructions**
We will process Personal Data only on documented instructions from the Controller, which include:
1. These Terms of Service and this DPA
2. Use of the Services per documentation
3. API calls and configuration settings
4. Support requests and email instructions

**4.2 Additional Instructions**
Additional or alternative instructions must be:
- Provided in writing (email acceptable)
- Consistent with the Terms of Service
- Technically feasible
- Confirmed by us in writing

**4.3 Unlawful Instructions**
If we believe an instruction violates Data Protection Laws, we will:
1. Inform the Controller immediately
2. Suspend execution of the instruction until clarified
3. Not be liable for non-performance during suspension

**4.4 Purpose Limitation**
We will not process Personal Data for any purpose other than those specified in the Controller's instructions.

## 5. Security Measures

**5.1 Technical and Organizational Measures**
We implement appropriate technical and organizational measures (TOMs) to ensure a level of security appropriate to the risk, including:

### Technical Safeguards
- **Encryption at Rest**: AES-256 encryption for sensitive data (passwords, SSH keys, database credentials)
- **Encryption in Transit**: TLS 1.3 for all data transmission
- **Access Control**: Role-Based Access Control (RBAC) with least privilege principle
- **Authentication**: Multi-factor authentication (MFA) available
- **Network Security**: Firewall rules limiting access to essential ports only
- **Intrusion Detection**: Real-time monitoring and alerting
- **Vulnerability Management**: Regular security scanning and patch management
- **Backup Encryption**: All backups encrypted with AES-256
- **Key Management**: Automated SSH key rotation every 90 days
- **Audit Logging**: Tamper-evident hash chain for critical operations

### Organizational Safeguards
- **Access Limitation**: Personal Data access restricted to authorized personnel only
- **Background Checks**: Employee screening per local laws
- **Confidentiality Agreements**: All personnel bound by confidentiality obligations
- **Security Training**: Regular security awareness training
- **Incident Response Plan**: Documented procedures for security incidents
- **Business Continuity**: Disaster recovery and backup procedures
- **Vendor Management**: Security assessment of all sub-processors
- **Data Minimization**: Collect and retain only necessary data
- **Tenant Isolation**: Strict segregation between customer accounts

**5.2 Security Documentation**
Detailed security measures are documented in Annex B - Technical and Organizational Measures (available upon request).

**5.3 Security Updates**
We will review and update security measures regularly to maintain appropriate security level as technology and threats evolve.

**5.4 Controller Assistance**
We will assist Controller in ensuring compliance with GDPR Articles 32-36 (security, breach notification, DPIA).

## 6. Sub-processing

**6.1 General Authorization**
Controller provides general authorization to engage sub-processors, subject to this Section 6.

**6.2 Current Sub-processors**
The current list of sub-processors is set out in Annex C and includes:

| Sub-processor | Service | Location | Safeguards |
|--------------|---------|----------|------------|
| Stripe Inc. | Payment processing | United States | SCCs, EU-US DPF |
| [EMAIL PROVIDER] | Email delivery | [LOCATION] | [SAFEGUARDS] |
| [CLOUD PROVIDER] | Infrastructure hosting | [LOCATION] | [SAFEGUARDS] |

**Updated List**: https://[YOUR-DOMAIN].com/legal/sub-processors

**6.3 Sub-processor Requirements**
Before engaging any sub-processor, we will:
1. Conduct due diligence on security and privacy practices
2. Ensure sub-processor enters into a written agreement imposing same obligations as this DPA
3. Remain fully liable to Controller for sub-processor's performance

**6.4 Change Notification**
- **Notice Period**: 30 days' notice before adding or replacing sub-processors
- **Notification Method**: Email to account owner and billing contact
- **Objection Right**: Controller may object on reasonable data protection grounds within 14 days
- **Resolution**: If objection cannot be resolved, Controller may terminate affected Services and receive pro-rata refund

**6.5 Sub-processor Audits**
Controller may request evidence of sub-processor compliance with this DPA.

## 7. Data Subject Rights

**7.1 Assistance Obligation**
We will assist Controller in responding to Data Subject rights requests, including:
- Right of access (Article 15)
- Right to rectification (Article 16)
- Right to erasure / "right to be forgotten" (Article 17)
- Right to restriction of processing (Article 18)
- Right to data portability (Article 20)
- Right to object (Article 21)

**7.2 Request Handling**
- **Direct Requests**: If Data Subject contacts us directly, we will forward to Controller within 48 hours
- **Response Time**: We will assist Controller within 7 days of request
- **Tools Provided**: Account settings and export functionality to facilitate rights exercise
- **Fees**: Assistance is included in Services; excessive requests may incur reasonable fees

**7.3 Data Export (Portability)**
We provide data export functionality:
- **Format**: JSON (machine-readable, structured)
- **Scope**: All Personal Data and service configurations
- **Access**: Account Settings > Export Data
- **Timeline**: Immediate export for standard data volumes; up to 48 hours for large datasets

**7.4 Data Deletion (Erasure)**
We provide data deletion functionality:
- **Method**: Account Settings > Delete Account or email privacy@[YOUR-DOMAIN].com
- **Timeline**: 30-day grace period, then permanent deletion
- **Immediate Deletion**: Available upon request (forfeits recovery period)
- **Verification**: Confirmation email sent after deletion completion
- **Exceptions**: Billing records retained for 7 years (legal obligation)

## 8. Personal Data Breach Notification

**8.1 Breach Definition**
A breach of security leading to accidental or unlawful destruction, loss, alteration, unauthorized disclosure of, or access to Personal Data.

**8.2 Notification to Controller**
We will notify Controller of any Personal Data breach:
- **Timeline**: Without undue delay, maximum 48 hours after becoming aware
- **Method**: Email to account owner and billing contact; severity-dependent phone call
- **Contact**: security@[YOUR-DOMAIN].com

**8.3 Breach Information**
Notification will include (to the extent known):
1. **Nature of Breach**: Description of incident and categories/volumes of data affected
2. **Contact Point**: Name and contact details of our Data Protection Officer (dpo@[YOUR-DOMAIN].com)
3. **Consequences**: Likely consequences of the breach
4. **Mitigation**: Measures taken or proposed to address breach and mitigate harm
5. **Timeline**: Timeline of events and discovery

**8.4 Controller's Notification Obligations**
Controller is responsible for:
- Notifying Supervisory Authority within 72 hours (if required per GDPR Article 33)
- Notifying affected Data Subjects (if required per GDPR Article 34)
- Determining risk level and notification requirements

**8.5 Cooperation**
We will cooperate with Controller's breach investigation and response, including:
- Providing additional information as it becomes available
- Preserving evidence for forensic analysis
- Implementing remediation measures
- Documenting incident per GDPR Article 33(5)

**8.6 Breach Register**
We maintain an internal breach register documenting all breaches, effects, and remedial actions per GDPR Article 33(5).

## 9. Data Protection Impact Assessment (DPIA)

**9.1 Assistance Obligation**
We will assist Controller in conducting Data Protection Impact Assessments (DPIAs) when required by GDPR Article 35.

**9.2 Information Provided**
We will provide:
- Description of processing operations and purposes
- Assessment of necessity and proportionality
- Assessment of risks to Data Subject rights
- Security measures implemented (Annex B)
- Sub-processor information (Annex C)

**9.3 Prior Consultation**
If DPIA indicates high risk and Controller must consult Supervisory Authority (Article 36), we will provide reasonable assistance.

## 10. Audits and Inspections

**10.1 Audit Rights**
Controller has the right to audit our compliance with this DPA, including:
- **Frequency**: Once per year, or more frequently if required by Supervisory Authority
- **Scope**: Processing activities, security measures, sub-processor compliance
- **Notice**: 30 days' advance written notice (7 days for authority-mandated audits)

**10.2 Audit Methods**

**Option 1: Third-Party Certifications** (Preferred)
We will provide:
- SOC 2 Type II reports (when available)
- ISO 27001 certification (when available)
- Independent security audit reports
- Sub-processor certifications

**Option 2: Questionnaire**
Controller may submit written questionnaire; we will respond within 30 days.

**Option 3: On-Site Audit**
- Conducted by Controller or independent third-party auditor
- Reasonable scope and duration (typically 1-2 days)
- During business hours with minimal operational disruption
- Subject to confidentiality agreement
- Costs borne by Controller
- We may require security clearance for auditors

**10.3 Audit Confidentiality**
All information obtained during audits is confidential and may not be disclosed to third parties (except as required by law or Supervisory Authority).

**10.4 Remediation**
If audit reveals non-compliance, we will:
1. Acknowledge findings within 7 days
2. Provide remediation plan within 30 days
3. Implement corrections within reasonable timeframe
4. Provide evidence of remediation

## 11. Data Deletion and Return

**11.1 End of Processing**
Upon termination of Services or Controller's written request, we will:

**Option 1: Deletion** (Default)
- Delete all Personal Data within 30 days
- Provide written certification of deletion upon request

**Option 2: Return**
- Export all Personal Data in JSON format
- Provide download link valid for 30 days
- Delete after Controller confirms receipt

**11.2 Retention Exceptions**
We may retain Personal Data only to the extent and for such period as required by applicable law (e.g., 7-year tax record retention), provided:
- Data is isolated and protected from further processing
- Data is used solely for compliance purposes
- Data is deleted when retention obligation expires

**11.3 Backup Deletion**
Personal Data in backups will be deleted or overwritten per our backup rotation schedule (maximum 90 days).

**11.4 Sub-processor Deletion**
We will ensure all sub-processors delete or return Personal Data per same requirements.

## 12. International Data Transfers

**12.1 Transfer Mechanisms**
Personal Data may be transferred to and processed in:
- **Primary Location**: [YOUR PRIMARY DATA CENTER LOCATION]
- **Backup Location**: [YOUR BACKUP DATA CENTER LOCATION]

For transfers from EEA/UK to third countries, we rely on:

**Option 1: Adequacy Decisions**
- EU Commission adequacy decisions (GDPR Article 45)
- UK adequacy regulations

**Option 2: Standard Contractual Clauses (SCCs)**
- EU Commission SCCs 2021/914 (Module 2: Controller-to-Processor)
- UK International Data Transfer Agreement (IDTA)
- SCCs incorporated as Annex A to this DPA

**Option 3: EU-US Data Privacy Framework**
- For sub-processors certified under DPF (e.g., Stripe)
- Verification: https://www.dataprivacyframework.gov/

**12.2 EEA Data Residency Option**
Enterprise customers may request EEA-only data storage:
- Contact sales@[YOUR-DOMAIN].com for pricing and availability
- Data stored exclusively in EU data centers
- Limited sub-processors with EEA presence

**12.3 Supplementary Measures**
In addition to SCCs, we implement supplementary technical measures:
- Encryption of data in transit and at rest
- Pseudonymization where feasible
- Strict access controls and authentication
- Contractual commitments from sub-processors

**12.4 Government Access Requests**
If we receive legal process to disclose Personal Data:
1. We will notify Controller unless legally prohibited
2. We will provide minimum necessary data
3. We will challenge overly broad requests where feasible
4. We maintain a transparency report (available upon request)

## 13. Liability and Indemnification

**13.1 Liability Allocation**
- **GDPR Article 82(2)**: Each party is liable for damage caused by Processing that violates GDPR
- **Chain of Responsibility**: Processor exempt from liability if it proves it is not in any way responsible for the damage
- **Joint Liability**: If both parties are responsible, each shall be held liable for the entire damage

**13.2 Indemnification**
We will indemnify Controller against fines, penalties, and damages resulting from our:
- Violation of this DPA
- Processing outside of documented instructions
- Failure to implement appropriate security measures
- Breach of GDPR obligations as Processor

**Exclusions**: No indemnification for Controller's violations, misuse, or unlawful instructions.

**13.3 Liability Limitations**
Subject to Section 13.1 and mandatory law:
- Liability caps in Terms of Service apply
- Exclusions for consequential damages apply
- **Exception**: Liability caps do NOT apply to data breach indemnification or gross negligence

## 14. Term and Termination

**14.1 Effective Date**
This DPA takes effect on the date Controller accepts the Terms of Service and continues until termination of all Services.

**14.2 Survival**
Sections that by their nature should survive termination will continue, including:
- Section 11 (Data Deletion and Return)
- Section 13 (Liability and Indemnification)
- Section 10 (Audits - for 1 year post-termination)

**14.3 Termination for DPA Breach**
Controller may terminate Services immediately if we materially breach this DPA and fail to cure within 30 days of written notice.

## 15. General Provisions

**15.1 Entire Agreement**
This DPA, together with the Terms of Service and annexed SCCs, constitutes the entire data processing agreement.

**15.2 Amendment**
Amendments must be in writing and signed by both parties, except:
- Updates to sub-processor list (Annex C) per Section 6.4
- Updates to security measures (Annex B) that enhance security

**15.3 Conflict**
In case of conflict between DPA and Terms of Service, DPA prevails for data protection matters.

**15.4 Severability**
If any provision is invalid, the remaining provisions continue in effect. Invalid provisions will be replaced with valid provisions reflecting the parties' intent.

**15.5 Governing Law**
This DPA is governed by the laws of [YOUR JURISDICTION], subject to mandatory provisions of GDPR and local data protection laws.

**15.6 Supervisory Authority Competence**
Disputes with a Supervisory Authority regarding this DPA fall under the jurisdiction and powers of that authority.

## 16. Contact Information

### Data Protection Officer (DPO)
**Email**: dpo@[YOUR-DOMAIN].com
**Postal Address**:
[YOUR COMPANY NAME]
Data Protection Officer
[STREET ADDRESS]
[CITY, STATE/PROVINCE POSTAL CODE]
[COUNTRY]

### Security Incidents
**Email**: security@[YOUR-DOMAIN].com
**Phone**: [EMERGENCY CONTACT NUMBER] (24/7 for critical incidents)

### Legal and Compliance
**Email**: legal@[YOUR-DOMAIN].com

---

## Annexes

### Annex A: Standard Contractual Clauses (SCCs)
[The EU Commission Standard Contractual Clauses 2021/914, Module 2 (Controller-to-Processor) are incorporated by reference. Full text available at: https://[YOUR-DOMAIN].com/legal/sccs]

**Key Provisions:**
- **Module**: Module 2 (Controller to Processor)
- **Clause 7**: Docking clause (optional)
- **Clause 9**: Use of sub-processors per Section 6 of this DPA
- **Clause 13**: Supervision by EEA Supervisory Authority
- **Clause 17**: Governing law: Ireland (or other EEA Member State)
- **Clause 18**: Forum: Courts of Ireland (or other EEA Member State)

**Completion of SCCs:**
- **Annex I.A** (Controller details): Completed by Controller
- **Annex I.B** (Processor details): [YOUR COMPANY NAME], [ADDRESS]
- **Annex I.C** (Competent Supervisory Authority): Controller's local authority
- **Annex II** (Technical and Organizational Measures): See Annex B below
- **Annex III** (Sub-processors): See Annex C below

### Annex B: Technical and Organizational Measures (TOMs)
[Full security documentation available upon request to legal@[YOUR-DOMAIN].com]

**Summary** (see Section 5.1 for details):
- Encryption: AES-256 (rest), TLS 1.3 (transit)
- Access Control: RBAC, MFA, least privilege
- Network Security: Firewall, IDS/IPS, DDoS protection
- Monitoring: Real-time security monitoring and alerting
- Audit: Tamper-evident audit logs with hash chains
- Backup: Encrypted backups with configurable retention
- Incident Response: 72-hour breach notification
- Personnel: Background checks, confidentiality agreements, training
- Physical Security: Data center certifications (ISO 27001, SOC 2)

### Annex C: Sub-processors

| Sub-processor | Service | Location | Data Processed | Safeguards |
|--------------|---------|----------|----------------|------------|
| Stripe Inc. | Payment processing | United States | Billing email, payment tokens | SCCs, EU-US Data Privacy Framework |
| [EMAIL PROVIDER] | Email delivery | [LOCATION] | Email addresses, message content | [SCCs / Adequacy / DPF] |
| [CLOUD PROVIDER] | Infrastructure hosting | [LOCATION] | All service data (encrypted) | [SCCs / Adequacy] |

**Updated List**: https://[YOUR-DOMAIN].com/legal/sub-processors
**Change Notification**: 30 days via email (per Section 6.4)

---

## Signature and Acceptance

**Processor** ([YOUR COMPANY NAME]):

By providing the Services, we agree to be bound by this DPA.

Signed: ______________________________
Name: [AUTHORIZED SIGNATORY]
Title: [TITLE]
Date: January 2, 2026

---

**Controller** (Customer):

By accepting the Terms of Service, you agree to be bound by this DPA.

Acceptance: Via online acceptance of Terms of Service or signed Order Form.

---

**Version**: 1.0
**Effective Date**: January 2, 2026
**Last Updated**: January 2, 2026

**This is a template for informational purposes. Consult with a qualified attorney for legal advice specific to your situation.**
