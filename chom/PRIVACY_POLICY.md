# Privacy Policy

**Last Updated: January 2, 2026**

**This is a template for informational purposes. Consult with a qualified attorney for legal advice specific to your situation.**

## 1. Introduction

[COMPANY NAME] ("we", "us", "our") operates the CHOM - Cloud Hosting & Observability Manager platform (the "Service"). This Privacy Policy explains how we collect, use, disclose, and protect your personal information in compliance with the General Data Protection Regulation (GDPR) and other applicable privacy laws.

**Data Controller:**
- Company Name: [YOUR COMPANY NAME]
- Registered Address: [YOUR REGISTERED ADDRESS]
- Contact Email: privacy@[YOUR-DOMAIN].com
- Data Protection Officer: dpo@[YOUR-DOMAIN].com

## 2. Legal Basis for Processing

We process personal data under the following legal bases (GDPR Article 6):

1. **Contract Performance** (Article 6(1)(b)): Processing necessary to provide the Service
2. **Consent** (Article 6(1)(a)): Where you have given explicit consent
3. **Legitimate Interests** (Article 6(1)(f)): For security, fraud prevention, and service improvement
4. **Legal Obligation** (Article 6(1)(c)): Compliance with tax, accounting, and regulatory requirements

## 3. Personal Data We Collect

### 3.1 Account Information
- **Data Collected**: Name, email address, password (encrypted), organization name
- **Purpose**: Account creation and authentication
- **Legal Basis**: Contract performance
- **Retention**: Until account deletion + 30 days for backup retention

### 3.2 Billing Information
- **Data Collected**: Billing email, Stripe customer ID, payment card details (tokenized)
- **Purpose**: Payment processing and invoicing
- **Legal Basis**: Contract performance
- **Retention**: 7 years for tax/accounting compliance
- **Note**: Payment card details are processed by Stripe (PCI DSS compliant)

### 3.3 Technical Information
- **Data Collected**: IP addresses, browser type, device information, access logs
- **Purpose**: Security, fraud prevention, service operation
- **Legal Basis**: Legitimate interest
- **Retention**: 90 days for security logs

### 3.4 Usage Data
- **Data Collected**: Sites created, VPS allocations, backup operations, API calls
- **Purpose**: Service delivery, usage-based billing, performance optimization
- **Legal Basis**: Contract performance and legitimate interest
- **Retention**: Duration of subscription + 90 days

### 3.5 Communication Data
- **Data Collected**: Support tickets, email correspondence, team invitations
- **Purpose**: Customer support and team collaboration
- **Legal Basis**: Contract performance and legitimate interest
- **Retention**: 3 years for support records

### 3.6 Site and Infrastructure Data
- **Data Collected**: Domain names, SSL certificates, server configurations, site backups
- **Purpose**: Service delivery and backup/restore functionality
- **Legal Basis**: Contract performance
- **Retention**: Active sites: duration of service; Deleted sites: 30 days for recovery

### 3.7 Audit and Security Logs
- **Data Collected**: User actions, operations, security events, hash chains
- **Purpose**: Security, fraud detection, compliance, tamper detection
- **Legal Basis**: Legitimate interest and legal obligation
- **Retention**: 1 year minimum for audit logs

## 4. How We Use Your Data

We use your personal data for:

1. **Service Delivery**: Provisioning sites, managing VPS servers, performing backups
2. **Authentication & Authorization**: Account access and role-based permissions
3. **Billing**: Subscription management, invoicing, payment processing via Stripe
4. **Security**: Fraud prevention, intrusion detection, access control
5. **Support**: Responding to inquiries and resolving technical issues
6. **Compliance**: Meeting legal obligations for data retention and reporting
7. **Service Improvement**: Performance monitoring, bug fixes, feature development
8. **Marketing**: Only with explicit consent; you can opt-out anytime

## 5. Data Sharing and Third-Party Processors

We share data only as necessary with the following third-party processors:

### 5.1 Payment Processing
- **Processor**: Stripe Inc.
- **Data Shared**: Billing email, payment information
- **Purpose**: Payment processing
- **Location**: United States (EU-US Data Privacy Framework certified)
- **DPA**: Available at https://stripe.com/privacy-center/legal

### 5.2 Email Services
- **Processor**: [SendGrid/Mailgun/Brevo - CONFIGURE YOUR PROVIDER]
- **Data Shared**: Email addresses, email content
- **Purpose**: Transactional emails, team invitations
- **Location**: [PROVIDER LOCATION]
- **DPA**: [LINK TO PROVIDER DPA]

### 5.3 Observability Stack
- **Processors**: Prometheus, Loki, Grafana (self-hosted or cloud)
- **Data Shared**: Performance metrics, logs (tenant-isolated)
- **Purpose**: Monitoring, alerting, performance analysis
- **Location**: [YOUR INFRASTRUCTURE LOCATION]

### 5.4 Infrastructure Providers
- **Processor**: [YOUR VPS/CLOUD PROVIDER]
- **Data Shared**: All service data (encrypted)
- **Purpose**: Hosting and infrastructure
- **Location**: [PROVIDER LOCATION]
- **DPA**: [LINK TO PROVIDER DPA]

### 5.5 No Data Selling
We DO NOT sell, rent, or trade your personal data to third parties for marketing purposes.

## 6. International Data Transfers

If you are located in the European Economic Area (EEA) or United Kingdom:

- **Primary Data Location**: [YOUR PRIMARY DATA CENTER LOCATION]
- **Transfer Mechanisms**:
  - Standard Contractual Clauses (SCCs) for EU-to-US transfers
  - Adequacy decisions where available
  - EU-US Data Privacy Framework for certified processors

- **Your Rights**: You have the right to obtain information about safeguards for international transfers

## 7. Your GDPR Rights

You have the following rights under GDPR:

### 7.1 Right of Access (Article 15)
Request a copy of all personal data we hold about you.

**How to Exercise**: Email privacy@[YOUR-DOMAIN].com or use in-app export feature
**Response Time**: Within 30 days

### 7.2 Right to Rectification (Article 16)
Correct inaccurate or incomplete personal data.

**How to Exercise**: Update via account settings or email privacy@[YOUR-DOMAIN].com
**Response Time**: Within 30 days

### 7.3 Right to Erasure / "Right to be Forgotten" (Article 17)
Request deletion of your personal data.

**How to Exercise**: Account Settings > Delete Account or email privacy@[YOUR-DOMAIN].com
**Response Time**: Within 30 days
**Exceptions**: We may retain data required for legal obligations (e.g., tax records for 7 years)

### 7.4 Right to Restriction of Processing (Article 18)
Request limitation on how we process your data.

**How to Exercise**: Email privacy@[YOUR-DOMAIN].com
**Response Time**: Within 30 days

### 7.5 Right to Data Portability (Article 20)
Receive your data in a structured, machine-readable format (JSON).

**How to Exercise**: Account Settings > Export Data or email privacy@[YOUR-DOMAIN].com
**Response Time**: Within 30 days
**Format**: JSON export including all personal data and service configurations

### 7.6 Right to Object (Article 21)
Object to processing based on legitimate interests or for marketing.

**How to Exercise**: Email privacy@[YOUR-DOMAIN].com or use opt-out links
**Response Time**: Immediate for marketing; within 30 days for other processing

### 7.7 Right to Withdraw Consent (Article 7(3))
Withdraw consent for processing based on consent.

**How to Exercise**: Account Settings or email privacy@[YOUR-DOMAIN].com
**Effect**: Does not affect lawfulness of processing before withdrawal

### 7.8 Right to Lodge a Complaint
File a complaint with your national data protection authority.

**EU Supervisory Authorities**: https://edpb.europa.eu/about-edpb/board/members_en
**UK ICO**: https://ico.org.uk/make-a-complaint/

## 8. Data Security Measures

We implement industry-standard security measures:

### Technical Safeguards
- **Encryption at Rest**: AES-256 encryption for sensitive data (passwords, SSH keys)
- **Encryption in Transit**: TLS 1.3 for all data transmission
- **Password Security**: Bcrypt hashing with per-user salt
- **API Security**: Laravel Sanctum token-based authentication
- **SSH Key Security**: Encrypted storage with key rotation every 90 days

### Organizational Safeguards
- **Access Control**: Role-Based Access Control (Owner, Admin, Member, Viewer)
- **Multi-Factor Authentication**: Optional 2FA for enhanced security
- **Audit Logging**: Tamper-evident hash chain for all critical operations
- **Tenant Isolation**: Strict data segregation between organizations
- **Security Monitoring**: Real-time intrusion detection and alerting
- **Incident Response**: 72-hour breach notification procedure (GDPR compliant)

### Infrastructure Security
- **Firewall**: Configured to allow only necessary ports (80, 443, 22)
- **Regular Updates**: Automated security patch deployment
- **Backup Encryption**: All backups encrypted with AES-256
- **Network Isolation**: Tenant data isolated at infrastructure level

## 9. Data Retention

| Data Type | Retention Period | Justification |
|-----------|-----------------|---------------|
| Account Data | Active account + 30 days | Service delivery + recovery period |
| Billing Records | 7 years after last transaction | Tax/accounting legal requirement |
| Audit Logs | 1 year minimum | Security and compliance |
| Security Logs | 90 days | Fraud prevention and investigation |
| Support Tickets | 3 years | Customer service quality |
| Site Backups | Per retention policy (configurable) | Data recovery service |
| Deleted Sites | 30 days | Accidental deletion recovery |
| Usage Metrics | Duration of subscription + 90 days | Billing accuracy |

After retention periods expire, data is securely deleted and cannot be recovered.

## 10. Cookies and Tracking

### 10.1 Essential Cookies (No Consent Required)
- **Session Cookie**: `chom_session` - Authentication and session management
- **CSRF Token**: `XSRF-TOKEN` - Security protection against cross-site attacks
- **Duration**: Session or until logout

### 10.2 Analytics Cookies (Consent Required)
We do not use third-party analytics cookies by default. If implemented:
- **Provider**: [YOUR ANALYTICS PROVIDER]
- **Purpose**: Website usage statistics
- **Consent**: Required before activation
- **Opt-out**: Cookie banner settings

### 10.3 Your Cookie Choices
- **Browser Settings**: Configure your browser to block cookies
- **Consent Management**: Update preferences in Cookie Settings
- **Impact**: Blocking essential cookies may prevent platform functionality

See our [Cookie Policy](#cookie-policy) for detailed information.

## 11. Children's Privacy

CHOM is a business-to-business (B2B) service not intended for children under 16. We do not knowingly collect data from children. If you become aware that a child has provided personal data, contact us immediately at privacy@[YOUR-DOMAIN].com for deletion.

## 12. Automated Decision-Making

We use limited automated processing:

- **Usage Limit Enforcement**: Automatic blocking when tier limits exceeded
- **Fraud Detection**: Automated flagging of suspicious activity
- **No Profiling**: We do not create profiles for marketing or advertising

You have the right to object to automated decision-making under GDPR Article 22.

## 13. Data Breach Notification

In the event of a personal data breach:

1. **Internal Detection**: Within 24 hours of discovery
2. **Risk Assessment**: Within 48 hours
3. **Supervisory Authority Notification**: Within 72 hours (if high risk)
4. **User Notification**: Without undue delay (if high risk to your rights)
5. **Breach Register**: Maintained per GDPR Article 33(5)

**Contact for Breaches**: security@[YOUR-DOMAIN].com

## 14. Changes to This Privacy Policy

We may update this Privacy Policy to reflect:
- Changes in legal requirements
- New features or services
- Feedback from users or regulators

**Notification Method**:
- Email notification for material changes
- In-app notification
- Updated "Last Updated" date at top of policy

**Your Continued Use**: Constitutes acceptance of updated policy after 30 days notice for material changes.

## 15. Contact Information

### General Privacy Inquiries
**Email**: privacy@[YOUR-DOMAIN].com
**Response Time**: Within 5 business days

### Data Protection Officer
**Email**: dpo@[YOUR-DOMAIN].com
**Response Time**: Within 30 days for rights requests

### Postal Address
[YOUR COMPANY NAME]
[STREET ADDRESS]
[CITY, POSTAL CODE]
[COUNTRY]

### Supervisory Authority
If you are in the EU/EEA, you may contact your local data protection authority:
https://edpb.europa.eu/about-edpb/board/members_en

## 16. Legal Framework Compliance

This Privacy Policy complies with:

- ✅ General Data Protection Regulation (GDPR) - EU Regulation 2016/679
- ✅ UK GDPR and Data Protection Act 2018
- ✅ California Consumer Privacy Act (CCPA) - where applicable
- ✅ ePrivacy Directive 2002/58/EC (as amended)

---

**GDPR Article References:**
- Article 6: Lawfulness of processing
- Article 7: Conditions for consent
- Article 12: Transparent information
- Article 13-14: Information to be provided
- Article 15-22: Data subject rights
- Article 32: Security of processing
- Article 33-34: Breach notification
- Article 44-50: International transfers

---

**This is a template for informational purposes. Consult with a qualified attorney for legal advice specific to your situation.**
