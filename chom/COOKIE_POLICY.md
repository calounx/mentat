# Cookie Policy

**Last Updated: January 2, 2026**

**This is a template for informational purposes. Consult with a qualified attorney for legal advice specific to your situation.**

## 1. Introduction

This Cookie Policy explains how CHOM - Cloud Hosting & Observability Manager ("we", "us", "our") uses cookies and similar tracking technologies on our platform. This policy complies with the EU ePrivacy Directive 2002/58/EC and GDPR requirements.

**Service Provider:**
- Company Name: [YOUR COMPANY NAME]
- Website: https://[YOUR-DOMAIN].com
- Contact: privacy@[YOUR-DOMAIN].com

## 2. What Are Cookies?

Cookies are small text files stored on your device (computer, tablet, smartphone) when you visit a website. They help websites remember your preferences, authenticate your identity, and provide functionality.

### Types of Cookies by Duration
- **Session Cookies**: Temporary cookies deleted when you close your browser
- **Persistent Cookies**: Remain on your device until expiration or manual deletion

### Types of Cookies by Purpose
- **Essential Cookies**: Required for website functionality (no consent needed)
- **Functional Cookies**: Enhance user experience (consent recommended)
- **Analytics Cookies**: Measure website usage (consent required)
- **Marketing Cookies**: Track for advertising (consent required)

## 3. Cookies We Use

### 3.1 Essential Cookies (No Consent Required)

These cookies are strictly necessary for the platform to function and cannot be disabled.

| Cookie Name | Purpose | Duration | Type | Legal Basis |
|-------------|---------|----------|------|-------------|
| `chom_session` | Maintains user session and authentication state | Session (until logout) | HTTP Only, Secure | Legitimate interest (GDPR Art. 6(1)(f)) |
| `XSRF-TOKEN` | Prevents Cross-Site Request Forgery attacks | Session | Secure | Legitimate interest (security) |
| `laravel_token` | API authentication token for REST API calls | 1 year or until revoked | HTTP Only, Secure | Contract performance (GDPR Art. 6(1)(b)) |
| `remember_web_*` | "Remember Me" functionality for persistent login | 5 years or until logout | HTTP Only, Secure | Consent (GDPR Art. 6(1)(a)) |

**Technical Details:**
- All cookies are set with `Secure` flag (HTTPS only)
- Session cookies use `HttpOnly` flag (not accessible via JavaScript)
- `SameSite=Lax` attribute for CSRF protection

### 3.2 Functional Cookies (Optional - Consent Recommended)

These cookies enhance user experience but are not strictly necessary.

| Cookie Name | Purpose | Duration | Consent Required |
|-------------|---------|----------|------------------|
| `chom_preferences` | Stores user interface preferences (theme, language) | 1 year | Recommended |
| `cookie_consent` | Records your cookie consent choices | 1 year | No (cookie consent cookie) |

### 3.3 Analytics Cookies (Consent Required)

**Current Implementation**: We do NOT use third-party analytics cookies by default.

If enabled in the future:
| Provider | Cookie Names | Purpose | Duration | Consent Required |
|----------|--------------|---------|----------|------------------|
| [ANALYTICS PROVIDER] | [COOKIE NAMES] | Website usage analytics | [DURATION] | Yes (GDPR Art. 6(1)(a)) |

**IP Anonymization**: If analytics are enabled, IP addresses are anonymized before processing.

### 3.4 Marketing Cookies (Not Used)

We do NOT use marketing or advertising cookies. We do not track users across websites.

## 4. Local Storage and Session Storage

In addition to cookies, we use browser storage mechanisms:

### Local Storage
| Item | Purpose | Retention |
|------|---------|-----------|
| `chom_ui_state` | Stores UI state (collapsed sidebars, table preferences) | Until manually cleared |
| `chom_draft_*` | Auto-saves form drafts to prevent data loss | 7 days |

### Session Storage
| Item | Purpose | Retention |
|------|---------|-----------|
| `chom_wizard_state` | Maintains state during multi-step wizards | Session only |

**Data Type**: Local/session storage contains NO personal data - only UI preferences and temporary state.

## 5. Third-Party Cookies

### 5.1 Stripe Payment Processing
When you add payment information, Stripe may set cookies:
- **Purpose**: Fraud prevention and secure payment processing
- **Privacy Policy**: https://stripe.com/privacy
- **Cookie Policy**: https://stripe.com/cookies-policy
- **Opt-out**: Not possible (required for payment processing)

### 5.2 Email Service Tracking
Our email service provider may use tracking pixels in emails:
- **Provider**: [YOUR EMAIL PROVIDER]
- **Purpose**: Delivery confirmation, open rates (for transactional emails only)
- **Opt-out**: Email preferences or contact privacy@[YOUR-DOMAIN].com

## 6. Your Cookie Choices

### 6.1 Cookie Consent Management

**Upon First Visit**: You will see a cookie consent banner with options:
- "Accept All Cookies" - Enables all cookies including optional ones
- "Essential Cookies Only" - Disables all non-essential cookies
- "Customize" - Choose which cookie categories to accept

**Update Preferences**: Access Cookie Settings anytime:
- Footer link: "Cookie Preferences"
- Account Settings > Privacy > Cookie Settings
- Email: privacy@[YOUR-DOMAIN].com

### 6.2 Browser Controls

All browsers allow cookie management:

**Google Chrome:**
1. Settings > Privacy and Security > Cookies and other site data
2. Choose "Block third-party cookies" or "Block all cookies"
3. Manage exceptions for specific sites

**Mozilla Firefox:**
1. Settings > Privacy & Security > Cookies and Site Data
2. Choose "Standard", "Strict", or "Custom" tracking protection
3. Manage Data to view/delete specific cookies

**Safari:**
1. Preferences > Privacy > Cookies and website data
2. Choose "Block all cookies" or manage by website

**Microsoft Edge:**
1. Settings > Privacy, search, and services > Cookies
2. Choose "Block third-party cookies" or "Block all cookies"

**Mobile Browsers**: Similar options available in mobile browser settings

### 6.3 Do Not Track (DNT)

**Current Status**: Our platform respects Do Not Track (DNT) browser signals.
- When DNT is enabled, we disable all optional cookies and tracking
- Essential cookies remain active for platform functionality
- Analytics and marketing cookies are automatically blocked

**How to Enable DNT**:
- Chrome: Settings > Privacy and Security > Send a "Do Not Track" request
- Firefox: Settings > Privacy & Security > Send websites a "Do Not Track" signal
- Safari: Preferences > Privacy > Website tracking > Ask websites not to track me

## 7. Impact of Blocking Cookies

### Essential Cookies Blocked
If you block essential cookies, the following may not work:
- ❌ User login and authentication
- ❌ Session persistence across pages
- ❌ CSRF protection (security risk)
- ❌ Shopping cart functionality (if applicable)
- ❌ Form submission security

**Recommendation**: Allow essential cookies for platform functionality

### Functional Cookies Blocked
If you block functional cookies:
- ⚠️ UI preferences reset each visit (theme, language)
- ⚠️ Need to reconfigure settings repeatedly
- ⚠️ Auto-save drafts disabled

**Impact**: Minor inconvenience, full functionality available

### Analytics Cookies Blocked
If you block analytics cookies:
- ✅ No impact on functionality
- ✅ Your usage not tracked for statistics

## 8. Cookie Lifespan and Deletion

### Automatic Deletion
| Cookie Type | Deletion Trigger |
|-------------|-----------------|
| Session Cookies | Browser closed or logout |
| Authentication Tokens | Token revocation or expiration |
| Remember Me Cookies | Manual logout or 5-year expiration |
| Preference Cookies | 1-year expiration or manual clearing |

### Manual Deletion
**Individual Sites**: Use browser settings to delete cookies for chom.com only
**All Sites**: Clear all browsing data (cookies, cache, history)

**Note**: Deleting cookies will log you out and reset preferences.

## 9. Consent Requirements Under GDPR and ePrivacy

### Legal Framework
- **ePrivacy Directive 2002/58/EC**: Requires consent for non-essential cookies
- **GDPR Article 6(1)(a)**: Consent must be freely given, specific, informed, and unambiguous
- **GDPR Article 7**: Right to withdraw consent anytime

### Our Compliance
✅ **Clear Information**: This Cookie Policy explains all cookies in detail
✅ **Granular Consent**: Choose specific cookie categories
✅ **Easy Withdrawal**: One-click consent withdrawal in Cookie Settings
✅ **No Cookie Walls**: Platform accessible with essential cookies only
✅ **Pre-consent Blocking**: Non-essential cookies not set until consent given
✅ **Consent Logging**: We record when and how you gave consent

### Consent Validity
- **Duration**: 12 months from last update
- **Reconfirmation**: Required if cookie purposes change
- **Renewal**: Consent banner shown if cookie policy significantly updated

## 10. Children's Privacy

Cookies on CHOM do not target or collect information from children under 16. If you believe a child has used our platform, contact privacy@[YOUR-DOMAIN].com.

## 11. Updates to This Cookie Policy

**Change Notification:**
- Email notification for material changes
- Updated "Last Updated" date at top
- Cookie consent banner re-shown if purposes change

**Review Frequency**: We review this policy annually or when:
- New cookies are added
- Third-party processors change
- Legal requirements updated

## 12. Cookie Audit Log

We maintain a cookie audit register per GDPR accountability requirements:

| Date | Change | Reason |
|------|--------|--------|
| 2026-01-02 | Initial Cookie Policy | Production launch |
| [DATE] | [CHANGE DESCRIPTION] | [JUSTIFICATION] |

## 13. Contact Information

### Cookie-Related Inquiries
**Email**: privacy@[YOUR-DOMAIN].com
**Subject Line**: "Cookie Policy Inquiry"
**Response Time**: 5 business days

### Data Protection Officer
**Email**: dpo@[YOUR-DOMAIN].com
**Subject Line**: "Cookie Consent Issue"

### Technical Support
**Email**: support@[YOUR-DOMAIN].com
**Subject Line**: "Cookie Technical Issue"

## 14. Regulatory Compliance

This Cookie Policy complies with:
- ✅ **EU ePrivacy Directive 2002/58/EC** - Cookie consent requirements
- ✅ **GDPR (EU) 2016/679** - Consent and transparency
- ✅ **UK PECR 2003** - Privacy and Electronic Communications Regulations
- ✅ **CNIL Guidelines** - French data protection authority cookie guidance
- ✅ **ICO Guidelines** - UK Information Commissioner's Office cookie guidance

## 15. Additional Resources

**Learn More About Cookies:**
- All About Cookies: https://www.allaboutcookies.org/
- ICO Cookie Guidance: https://ico.org.uk/for-organisations/guide-to-pecr/cookies-and-similar-technologies/

**GDPR Resources:**
- European Data Protection Board: https://edpb.europa.eu/
- Your Data Protection Rights: https://ec.europa.eu/info/law/law-topic/data-protection_en

---

## Appendix A: Technical Cookie Specifications

### Cookie Security Attributes

All CHOM cookies implement the following security measures:

```
Set-Cookie: chom_session=<value>;
  Secure;
  HttpOnly;
  SameSite=Lax;
  Path=/;
  Domain=[YOUR-DOMAIN].com;
  Max-Age=7200
```

**Attribute Explanations:**
- `Secure`: Cookie only sent over HTTPS (encrypted)
- `HttpOnly`: Cookie not accessible via JavaScript (XSS protection)
- `SameSite=Lax`: Prevents CSRF attacks while allowing normal navigation
- `Path=/`: Cookie available across entire domain
- `Domain`: Restricts cookie to our domain only
- `Max-Age`: Cookie lifespan in seconds

### Cookie Storage Limits
- **Maximum Cookie Size**: 4096 bytes per cookie
- **Maximum Cookies per Domain**: 50 cookies
- **Total Storage**: ~200KB maximum

**Our Usage**: We use minimal cookies to stay well under these limits.

---

**This is a template for informational purposes. Consult with a qualified attorney for legal advice specific to your situation.**
