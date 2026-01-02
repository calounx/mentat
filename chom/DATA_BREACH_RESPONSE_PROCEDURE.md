# Data Breach Response Procedure

**Last Updated: January 2, 2026**

This document outlines the data breach response procedures for CHOM - Cloud Hosting & Observability Manager in compliance with GDPR Articles 33-34.

## Executive Summary

**GDPR Breach Notification Requirements:**
- **72-Hour Rule**: Notify supervisory authority within 72 hours (Article 33)
- **Immediate User Notification**: Notify affected users without undue delay if high risk (Article 34)
- **Documentation**: Maintain breach register per Article 33(5)

**Contact Information:**
- **Security Incidents**: security@[YOUR-DOMAIN].com
- **Emergency Hotline**: [24/7 PHONE NUMBER]
- **Data Protection Officer**: dpo@[YOUR-DOMAIN].com

## 1. Definitions

**Personal Data Breach** (GDPR Article 4(12)):
> A breach of security leading to the accidental or unlawful destruction, loss, alteration, unauthorized disclosure of, or access to, personal data transmitted, stored or otherwise processed.

**Types of Breaches:**
1. **Confidentiality Breach**: Unauthorized or accidental disclosure
2. **Integrity Breach**: Unauthorized or accidental alteration
3. **Availability Breach**: Accidental or unauthorized loss of access

**High Risk Breach**:
A breach likely to result in high risk to individuals' rights and freedoms, requiring notification to data subjects.

## 2. Breach Response Team

### 2.1 Incident Response Team (IRT)

| Role | Responsibilities | Contact |
|------|-----------------|---------|
| **Incident Commander** | Overall coordination, decision authority | [NAME/TITLE] |
| **Data Protection Officer (DPO)** | GDPR compliance, authority notification | dpo@[YOUR-DOMAIN].com |
| **Security Lead** | Technical investigation, containment | security@[YOUR-DOMAIN].com |
| **Legal Counsel** | Legal obligations, liability assessment | legal@[YOUR-DOMAIN].com |
| **Communications Lead** | User notification, public relations | comms@[YOUR-DOMAIN].com |
| **Customer Success** | Customer support, impact assessment | support@[YOUR-DOMAIN].com |

### 2.2 Escalation Contacts

**Internal Escalation:**
1. Security Team (immediate)
2. DPO (within 1 hour)
3. Executive Team (within 2 hours for high-severity)
4. Board of Directors (within 24 hours for critical incidents)

**External Escalation:**
1. Supervisory Authority (within 72 hours if required)
2. Affected Customers (without undue delay if high risk)
3. Law Enforcement (if criminal activity suspected)
4. Cyber Insurance Provider (per policy terms)

## 3. Breach Detection and Identification

### 3.1 Detection Mechanisms

**Automated Detection:**
- Intrusion Detection System (IDS) alerts
- Security Information and Event Management (SIEM) anomalies
- Failed login attempt patterns
- Unauthorized database queries
- Unexpected data exports
- Encryption key access anomalies
- Hash chain integrity failures (audit log tampering)

**Manual Detection:**
- User reports of suspicious activity
- System administrator observations
- Security audit findings
- Third-party security researcher reports
- Sub-processor breach notifications

### 3.2 Initial Assessment (Within 1 Hour)

**Questions to Answer:**
1. **What happened?** Type of incident (confidentiality, integrity, availability)
2. **When?** Time of breach occurrence vs. detection
3. **Who?** Affected users, data subjects, scope
4. **What data?** Types and categories of personal data
5. **How many?** Number of affected individuals
6. **How severe?** Initial risk assessment (low/medium/high/critical)

**Documentation:**
Create incident ticket in internal system with:
- Incident ID
- Discovery time
- Discovery method
- Initial assessment
- Response team members assigned

## 4. Breach Response Process (6 Phases)

### Phase 1: Containment (0-2 Hours)

**Objective**: Stop the breach and prevent further unauthorized access.

**Actions:**
1. **Isolate Affected Systems**
   - Disconnect compromised servers from network (if safe to do so)
   - Revoke compromised credentials immediately
   - Disable affected user accounts
   - Block malicious IP addresses at firewall

2. **Preserve Evidence**
   - Take snapshots of affected systems
   - Capture logs before they rotate
   - Document system state
   - Do NOT destroy evidence

3. **Notify Response Team**
   - Alert all Incident Response Team members
   - Initiate war room (virtual or physical)
   - Assign roles per Section 2.1

**Containment Checklist:**
- [ ] Compromised systems identified and isolated
- [ ] Unauthorized access terminated
- [ ] Credentials rotated/revoked
- [ ] Evidence preserved
- [ ] Response team assembled
- [ ] Initial documentation created

### Phase 2: Investigation (2-24 Hours)

**Objective**: Understand the full scope and impact of the breach.

**Investigation Questions:**
1. **Attack Vector**: How did the breach occur?
2. **Scope**: What systems and data were affected?
3. **Attacker**: Who (if identifiable)? Internal/external?
4. **Persistence**: Are backdoors or malware present?
5. **Data Exfiltration**: Was data copied or exported?
6. **Duration**: When did unauthorized access begin?

**Technical Investigation:**
```bash
# Example investigation commands (Linux)
# Review authentication logs
grep -i "failed\|failure" /var/log/auth.log | tail -1000

# Check for unauthorized users
awk -F: '$3 >= 1000 {print $1}' /etc/passwd

# Review web server access logs
grep -E "POST|GET" /var/log/nginx/access.log | grep -v "200\|301" | tail -1000

# Database audit logs
# (Platform-specific queries)

# Network connections
netstat -antp | grep ESTABLISHED

# File integrity check
# Compare against known good state
```

**Data Impact Assessment:**
- **Personal Data Categories**: Names, emails, passwords, payment info, etc.
- **Volume**: Number of records affected
- **Sensitivity**: Special category data? Children's data?
- **Potential Harm**: What could attacker do with this data?

**Investigation Output:**
- Detailed incident timeline
- Root cause analysis
- Scope of data affected
- Evidence collection (logs, screenshots, forensics)

### Phase 3: Risk Assessment (Within 24 Hours)

**Objective**: Determine breach severity and notification obligations.

#### 3.1 Risk to Individuals (GDPR Article 33/34)

**Low Risk** (No notification required):
- Encrypted data with no key compromise
- Data already public
- No sensitive data involved
- Minimal impact on individual rights

**Medium Risk** (Authority notification required):
- Non-sensitive personal data
- Limited volume
- Low likelihood of harm
- Mitigating factors present

**High Risk** (Authority + individual notification required):
- Sensitive personal data (health, financial, children)
- Large volume of individuals
- High likelihood of identity theft, fraud, discrimination
- Special category data (GDPR Article 9)
- Lack of mitigating measures

**Risk Assessment Matrix:**

| Factor | Low Risk | Medium Risk | High Risk |
|--------|----------|-------------|-----------|
| Data Sensitivity | Public info only | Basic personal data | Financial, health, credentials |
| Volume | <10 individuals | 10-1,000 | >1,000 |
| Encryption | Encrypted, no key loss | Encrypted, key may be exposed | Unencrypted or key compromised |
| Special Categories | No | No | Yes (Art. 9 data) |
| Potential Harm | Minimal inconvenience | Financial loss possible | Identity theft, discrimination |
| Mitigating Factors | Strong controls in place | Some controls | No effective controls |

**Notification Decision Tree:**
```
Is it a personal data breach?
├─ No → Document reasoning, no notification required
└─ Yes → Continue

Is data encrypted with secure key not compromised?
├─ Yes → Low risk, may not require notification
└─ No → Continue

Is there high risk to individuals' rights and freedoms?
├─ No → Notify authority only (72 hours)
└─ Yes → Notify authority AND individuals (without undue delay)
```

#### 3.2 Documentation for Risk Assessment

**Required Information (GDPR Article 33(3)):**
1. Nature of breach (confidentiality, integrity, availability)
2. Categories and approximate number of data subjects
3. Categories and approximate number of personal data records
4. Likely consequences of breach
5. Measures taken or proposed to address breach
6. Measures to mitigate possible adverse effects

### Phase 4: Notification (Within 72 Hours)

#### 4.1 Supervisory Authority Notification (GDPR Article 33)

**Timeline**: Within 72 hours of becoming aware (unless unlikely to risk rights/freedoms)

**Lead Supervisory Authority** (For EU/EEA):
- Determined by location of main establishment
- If [YOUR COMPANY] is based in [COUNTRY]: [SUPERVISORY AUTHORITY NAME]
- Contact: [AUTHORITY EMAIL/PORTAL]

**UK**: Information Commissioner's Office (ICO)
- Report: https://ico.org.uk/for-organisations/report-a-breach/

**Notification Content (Article 33(3)):**

```
SUBJECT: Personal Data Breach Notification per GDPR Article 33

1. NATURE OF THE BREACH
   - Type: [Confidentiality/Integrity/Availability]
   - Date/Time of Breach: [YYYY-MM-DD HH:MM UTC]
   - Date/Time of Discovery: [YYYY-MM-DD HH:MM UTC]
   - Root Cause: [Description]

2. CONTACT POINT
   - Data Protection Officer: [NAME]
   - Email: dpo@[YOUR-DOMAIN].com
   - Phone: [DPO PHONE NUMBER]

3. DATA SUBJECTS AND RECORDS AFFECTED
   - Approximate number of data subjects: [NUMBER]
   - Categories of data subjects: [Customers, employees, etc.]
   - Approximate number of personal data records: [NUMBER]
   - Categories of data: [Names, emails, passwords, payment info, etc.]

4. LIKELY CONSEQUENCES
   - Potential impact: [Identity theft risk, financial fraud, etc.]
   - Severity assessment: [Low/Medium/High]
   - Justification: [Reasoning]

5. MEASURES TAKEN OR PROPOSED
   Containment:
   - [Describe immediate containment actions]

   Investigation:
   - [Describe investigation steps]

   Remediation:
   - [Describe fixes implemented]

   Mitigation:
   - [Describe measures to reduce harm to individuals]
   - [Credit monitoring, password reset assistance, etc.]

6. PHASED NOTIFICATION (if applicable)
   - If not all information available within 72 hours, state reasons
   - Commit to providing additional information without undue delay

ATTACHMENTS:
- Incident timeline
- Technical forensics report
- Affected user list (if requested by authority)

Submitted by: [YOUR COMPANY NAME]
Date: [YYYY-MM-DD HH:MM UTC]
Reference: Breach-[INCIDENT-ID]
```

**Notification Methods:**
- Online portal (if authority provides)
- Email to authority
- Secure file transfer (for sensitive details)

**Late Notification** (>72 hours):
Must include reasoned justification for delay

#### 4.2 Data Subject Notification (GDPR Article 34)

**Requirement**: Required when breach is likely to result in **high risk** to individuals.

**Timeline**: Without undue delay (typically within 72 hours)

**Notification Content (Article 34(2)):**

```
SUBJECT: Important Security Notice - Data Breach Notification

Dear [NAME],

We are writing to inform you of a security incident that may affect your personal data.

WHAT HAPPENED
On [DATE], we discovered [DESCRIPTION OF BREACH]. We immediately launched an investigation and took steps to secure our systems.

WHAT DATA WAS AFFECTED
The incident may have affected the following information:
- [List specific data types: names, emails, etc.]
- [Specify if passwords, payment info, etc. were involved]

WHAT WE ARE DOING
- [Containment measures taken]
- [Security improvements implemented]
- [Ongoing investigation and monitoring]

WHAT YOU SHOULD DO
1. [Specific action: Change password, monitor accounts, etc.]
2. [Additional recommendations]
3. [Resources provided: credit monitoring, support hotline]

SUPPORT AND ASSISTANCE
We are here to help. If you have questions or concerns:
- Email: security@[YOUR-DOMAIN].com
- Phone: [SUPPORT NUMBER]
- Hours: [24/7 or specify hours]

We sincerely apologize for this incident and any inconvenience it may cause. Protecting your data is our top priority, and we are taking all necessary steps to prevent this from happening again.

CONTACT INFORMATION
Data Protection Officer: dpo@[YOUR-DOMAIN].com

REGULATORY INFORMATION
You have the right to lodge a complaint with the data protection supervisory authority:
[SUPERVISORY AUTHORITY NAME]
[CONTACT INFORMATION]

Sincerely,
[YOUR COMPANY NAME]
[DATE]
```

**Notification Exemptions (Article 34(3)):**
No notification to individuals required if:
1. **Encryption**: Data protected by encryption and keys not compromised
2. **Subsequent Measures**: Measures taken ensure high risk no longer materializes
3. **Disproportionate Effort**: Too many individuals (use public communication instead)

**Public Communication** (if disproportionate effort):
- Public announcement on website
- Press release
- Email to known contacts
- Social media notification

#### 4.3 Customer/Controller Notification (B2B)

For CHOM customers (who are data controllers):
- Notify within 48 hours
- Provide detailed information for their own notification obligations
- Include Data Processing Agreement (DPA) reference

### Phase 5: Remediation (1-30 Days)

**Objective**: Fix vulnerabilities and prevent recurrence.

**Technical Remediation:**
1. **Patch Vulnerabilities**
   - Apply security updates
   - Fix code vulnerabilities
   - Update configurations

2. **Improve Security Controls**
   - Strengthen access controls
   - Enhance encryption
   - Implement additional monitoring
   - Add intrusion prevention measures

3. **Credential Rotation**
   - Force password resets for affected users
   - Rotate SSH keys
   - Regenerate API tokens
   - Update database credentials

4. **System Hardening**
   - Review and update firewall rules
   - Disable unnecessary services
   - Implement principle of least privilege
   - Enable additional security features

**Organizational Remediation:**
1. **Policy Updates**
   - Update security policies
   - Revise access control procedures
   - Enhance incident response plan

2. **Training**
   - Security awareness training for all staff
   - Specialized training for security team
   - Phishing simulation exercises

3. **Third-Party Review**
   - Engage external security auditors
   - Penetration testing
   - Security architecture review

**User Support:**
- Dedicated support line for affected users
- FAQ page for common questions
- Credit monitoring (if applicable)
- Identity theft protection (if applicable)

### Phase 6: Post-Incident Review (30-90 Days)

**Objective**: Learn from incident and improve future response.

**Post-Incident Report Contents:**
1. **Executive Summary**
   - Incident overview
   - Impact summary
   - Key lessons learned

2. **Detailed Timeline**
   - All events from breach to resolution
   - Response actions and timings

3. **Root Cause Analysis**
   - Technical cause
   - Process failures
   - Contributing factors

4. **Response Evaluation**
   - What went well
   - What went poorly
   - Response time analysis

5. **Improvements**
   - Technical improvements implemented
   - Process improvements
   - Training conducted
   - Policy updates

6. **Metrics**
   - Time to detection
   - Time to containment
   - Time to notification
   - Number of individuals affected
   - Cost of incident

**Post-Incident Actions:**
- Update incident response plan based on lessons learned
- Implement recommended improvements
- Schedule follow-up security audit
- Review and test updated procedures

## 5. Breach Register (GDPR Article 33(5))

### 5.1 Documentation Requirements

We maintain a register of all data breaches, including those not requiring notification.

**Breach Register Fields:**

| Field | Description | Example |
|-------|-------------|---------|
| Incident ID | Unique identifier | BR-2026-001 |
| Discovery Date | When breach was discovered | 2026-01-02 09:30 UTC |
| Breach Date | When breach occurred (if known) | 2026-01-01 14:00 UTC |
| Type | Confidentiality/Integrity/Availability | Confidentiality |
| Cause | Root cause | Compromised credentials |
| Data Affected | Categories of personal data | Names, emails, hashed passwords |
| Subjects Affected | Number of individuals | 1,247 |
| Risk Assessment | Low/Medium/High/Critical | High |
| Authority Notified | Yes/No, date | Yes, 2026-01-03 |
| Subjects Notified | Yes/No, date | Yes, 2026-01-03 |
| Containment Actions | Steps taken to stop breach | Credential rotation, system isolation |
| Remediation Actions | Fixes implemented | MFA enforcement, enhanced monitoring |
| Status | Open/Contained/Remediated/Closed | Closed |
| Lessons Learned | Key takeaways | Implement MFA for all admin accounts |

### 5.2 Breach Register Access

**Internal Access:**
- DPO: Full access
- Security Team: Full access
- Legal Counsel: Full access
- Executives: Read access
- Audit Committee: Read access

**External Access:**
- Supervisory Authority: Upon request
- External Auditors: Upon request with NDA

**Retention**: Breach register maintained indefinitely for accountability

## 6. Specific Breach Scenarios

### Scenario 1: Database Compromise

**Indicators:**
- Unauthorized database queries in logs
- Data export to unknown location
- Compromised database credentials

**Response:**
1. Immediately revoke database credentials
2. Block database access from external IPs
3. Review query logs to determine data accessed
4. Assess if encryption was in place
5. Notify if unencrypted sensitive data accessed

**Risk Level**: High (if unencrypted), Medium (if encrypted)

### Scenario 2: Ransomware Attack

**Indicators:**
- Files encrypted by malware
- Ransom note displayed
- System availability loss

**Response:**
1. Isolate affected systems immediately
2. Do NOT pay ransom (company policy + law enforcement guidance)
3. Restore from backups
4. Assess if data was exfiltrated before encryption
5. Notify authority (availability breach + potential confidentiality breach)

**Risk Level**: Medium to High (depending on exfiltration)

### Scenario 3: Employee Unauthorized Access

**Indicators:**
- Employee accessing data outside job function
- Unusual data exports
- Access during off-hours

**Response:**
1. Suspend employee access immediately
2. Investigate scope of unauthorized access
3. Review all actions performed by employee
4. HR investigation and potential termination
5. Notify if data was exfiltrated or misused

**Risk Level**: Medium to High (depending on data sensitivity and intent)

### Scenario 4: Third-Party Sub-processor Breach

**Indicators:**
- Notification from sub-processor (e.g., Stripe, email provider)
- Public disclosure of breach

**Response:**
1. Request detailed information from sub-processor
2. Assess if CHOM customer data was affected
3. Determine our notification obligations
4. Notify customers if their data affected
5. Review sub-processor relationship and DPA

**Risk Level**: Varies (depends on sub-processor's breach severity)

### Scenario 5: Lost or Stolen Device

**Indicators:**
- Employee reports laptop stolen
- Mobile device missing

**Response:**
1. Remotely wipe device if possible
2. Revoke device authentication
3. Change credentials accessible from device
4. Assess if data was encrypted
5. Notify if unencrypted personal data on device

**Risk Level**: Low (if encrypted), High (if unencrypted)

### Scenario 6: Misconfigured Access Controls

**Indicators:**
- Public S3 bucket discovered
- Database exposed to internet
- API endpoint without authentication

**Response:**
1. Immediately correct misconfiguration
2. Review access logs to determine if accessed
3. Assess scope of data exposure
4. Notify if evidence of unauthorized access

**Risk Level**: Low (if no access), High (if accessed)

## 7. Communication Templates

### 7.1 Internal Alert Template

```
TO: Incident Response Team
SUBJECT: [SEVERITY] Security Incident - [INCIDENT-ID]

INCIDENT SUMMARY
- Severity: [Critical/High/Medium/Low]
- Discovery Time: [TIMESTAMP]
- Affected Systems: [LIST]
- Estimated Impact: [DESCRIPTION]

IMMEDIATE ACTIONS REQUIRED
1. [ACTION 1]
2. [ACTION 2]

WAR ROOM
- Location: [VIRTUAL LINK or PHYSICAL LOCATION]
- Time: [IMMEDIATE or SCHEDULED TIME]

INCIDENT COMMANDER
[NAME] - [CONTACT]
```

### 7.2 Customer Notification Template

(See Section 4.2 for detailed template)

### 7.3 Press Statement Template (If Public Disclosure Required)

```
[YOUR COMPANY NAME] Security Incident Statement

[CITY, DATE] - [YOUR COMPANY NAME] is notifying customers of a security incident that occurred on [DATE]. We take the security of customer data extremely seriously and are taking immediate action.

WHAT HAPPENED
[Brief, factual description of incident]

WHAT DATA WAS INVOLVED
[General categories without revealing security details]

WHAT WE ARE DOING
We immediately [containment actions]. We have engaged [external security experts/law enforcement] and are conducting a thorough investigation.

WHAT CUSTOMERS SHOULD DO
[Specific recommendations]

SUPPORT
Affected customers have been directly notified. If you have questions:
- Email: security@[YOUR-DOMAIN].com
- Phone: [NUMBER]

We sincerely apologize for this incident and are committed to earning back the trust of our customers.

Media Contact:
[COMMUNICATIONS LEAD]
[EMAIL/PHONE]
```

## 8. Compliance Checklist

### GDPR Breach Notification Compliance

- [ ] Breach detected and documented
- [ ] Response team assembled within 1 hour
- [ ] Containment actions taken within 2 hours
- [ ] Investigation completed within 24 hours
- [ ] Risk assessment documented
- [ ] DPO consulted
- [ ] Legal counsel consulted
- [ ] Supervisory authority notified within 72 hours (if required)
- [ ] Data subjects notified without undue delay (if high risk)
- [ ] Breach register updated
- [ ] Customers (controllers) notified within 48 hours
- [ ] Remediation plan created and executed
- [ ] Post-incident review scheduled
- [ ] Improvements implemented
- [ ] Incident response plan updated

## 9. Training and Testing

### 9.1 Incident Response Training

**Frequency**: Quarterly

**Attendees**: All Incident Response Team members

**Topics**:
- GDPR breach notification requirements
- Breach response procedures
- Communication protocols
- Technical investigation techniques

### 9.2 Breach Response Drills

**Frequency**: Semi-annually (every 6 months)

**Scenarios**:
- Database compromise simulation
- Ransomware attack simulation
- Insider threat simulation
- Third-party breach notification

**Evaluation Criteria**:
- Time to detection
- Time to containment
- Notification timing
- Team coordination
- Documentation quality

### 9.3 Table-Top Exercises

**Frequency**: Annually

**Participants**:
- Executive team
- Incident Response Team
- Legal counsel
- Board representatives (if applicable)

**Objective**: Test decision-making and escalation procedures

## 10. Continuous Improvement

### 10.1 Procedure Review

This procedure is reviewed and updated:
- Annually (scheduled review)
- After each significant incident
- When GDPR or other regulations change
- When organizational changes occur

### 10.2 Metrics and KPIs

**Breach Response KPIs:**
- Mean Time to Detect (MTTD)
- Mean Time to Contain (MTTC)
- Mean Time to Notify (MTTN)
- Number of breaches per year
- Percentage of breaches meeting 72-hour notification requirement
- Cost per incident

**Target KPIs:**
- MTTD: <4 hours
- MTTC: <24 hours
- MTTN: <48 hours (authority), <72 hours (individuals)
- 72-hour compliance: 100%

---

**Document Owner**: Data Protection Officer
**Review Date**: January 2027
**Version**: 1.0
**Classification**: Internal - Confidential

**For Incident Reporting:**
- **Email**: security@[YOUR-DOMAIN].com
- **Phone**: [24/7 HOTLINE]
- **Emergency**: Immediately contact Incident Commander
