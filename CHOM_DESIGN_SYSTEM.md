# CHOM Design System: Refined Technical Elegance

**Version**: 2.0
**Date**: 2026-01-09
**Philosophy**: Infrastructure management deserves sophisticated design

---

## Design Philosophy

CHOM's redesign follows the principle of **"Refined Technical Elegance"** — bringing luxury hospitality aesthetics to infrastructure management. Think of it as managing your servers through a boutique hotel concierge service, not a data center.

### Key Differentiators

1. **Jewel-Tone Color Palette**: Deep emeralds, rich sapphires, warm champagnes instead of generic blues
2. **Sophisticated Typography**: Serif headlines (Crimson Pro) paired with refined sans-serif body (DM Sans)
3. **Subtle Animations**: Elegant micro-interactions that delight without distracting
4. **Premium Card System**: Floating cards with gradient accents that respond to interaction
5. **Generous Whitespace**: Breathing room that conveys quality and attention to detail

---

## Typography System

### Font Families

```css
--font-display: 'Crimson Pro', Georgia, serif;      /* Headlines, brand */
--font-sans: 'DM Sans', system-ui, sans-serif;      /* Body, UI elements */
--font-mono: 'JetBrains Mono', 'Fira Code', monospace; /* Technical content */
```

### Usage Guidelines

- **Display Font (Crimson Pro)**: Use for h1, h2, h3, brand name, and any element that needs elegance
- **Sans Font (DM Sans)**: Use for body text, buttons, labels, navigation
- **Mono Font (JetBrains Mono)**: Use for code snippets, server logs, IP addresses, technical identifiers

### Type Scale

```
h1: clamp(1.875rem, 4vw, 2.5rem)  // 30px-40px fluid
h2: clamp(1.5rem, 3vw, 2rem)      // 24px-32px fluid
h3: clamp(1.25rem, 2.5vw, 1.5rem) // 20px-24px fluid
body: 1rem (16px)
small: 0.875rem (14px)
```

---

## Color Palette

### Primary Colors (Jewel Tones)

#### Emerald (Success, Healthy, Primary Actions)
```
emerald-50:  #f0fdf7  // Lightest background
emerald-100: #dcfce8  // Light background
emerald-200: #bbf7d1  // Borders, light accents
emerald-500: #22c55e  // Status indicators
emerald-600: #059669  // Primary buttons, links
emerald-700: #047857  // Hover states, active links
emerald-800: #065f46  // Text on light backgrounds
```

#### Sapphire (Info, Secondary Actions)
```
sapphire-50:  #eff6ff  // Lightest background
sapphire-100: #dbeafe  // Light background
sapphire-200: #bfdbfe  // Borders
sapphire-500: #3b82f6  // Info indicators
sapphire-600: #2563eb  // Secondary buttons
sapphire-700: #1d4ed8  // Hover states
sapphire-800: #1e40af  // Text
```

#### Champagne (Warning, Attention)
```
champagne-50:  #fefce8  // Light background
champagne-100: #fef9c3  // Medium background
champagne-200: #fef08a  // Borders
champagne-500: #eab308  // Warning indicators
champagne-600: #ca8a04  // Warning text
champagne-800: #854d0e  // Dark warning text
```

#### Ruby (Error, Critical, Danger)
```
ruby-50:  #fef2f2  // Light background
ruby-100: #fee2e2  // Medium background
ruby-200: #fecaca  // Borders
ruby-500: #ef4444  // Error indicators
ruby-600: #dc2626  // Error buttons
ruby-700: #b91c1c  // Hover states
ruby-800: #991b1b  // Text
```

### Neutral Colors (Warm Stone Palette)

```
stone-50:  #fafaf9  // Page background (light)
stone-100: #f5f5f4  // Card backgrounds, alternating rows
stone-200: #e7e5e4  // Borders, dividers
stone-300: #d6d3d1  // Strong borders, disabled states
stone-400: #a8a29e  // Placeholders
stone-500: #78716c  // Muted text
stone-600: #57534e  // Secondary text
stone-700: #44403c  // Body text
stone-800: #292524  // Emphasis text
stone-900: #1c1917  // Headings, strong emphasis
```

---

## Component Library

### 1. Cards

**Sophisticated Card System with Gradient Accent**

```html
<div class="card">
    <div class="card-header">
        <h2>Card Title</h2>
    </div>
    <div class="card-body">
        <!-- Content -->
    </div>
</div>
```

**Features**:
- Subtle gradient top border (appears on hover)
- Soft shadows with hover lift effect
- Smooth transitions (300ms)
- Refined border radius (1rem)

### 2. Buttons

**Primary Button (Emerald Gradient)**
```html
<button class="btn btn-primary">
    <svg>...</svg>
    Action
</button>
```

**Secondary Button (White with Border)**
```html
<button class="btn btn-secondary">
    Action
</button>
```

**Features**:
- Ripple effect on click (expanding circle)
- Lift on hover with enhanced shadow
- Icon + text support
- Loading states

### 3. Status Badges

**Usage**:
```html
<!-- Healthy -->
<span class="status-badge status-healthy">
    <span class="status-dot healthy"></span>
    Healthy
</span>

<!-- Warning -->
<span class="status-badge status-warning">
    <span class="status-dot warning"></span>
    Warning
</span>

<!-- Critical -->
<span class="status-badge status-critical">
    <span class="status-dot critical"></span>
    Critical
</span>
```

**Features**:
- Gradient backgrounds
- Pulsing status dots
- Color-coded borders
- Uppercase text with letter-spacing

### 4. Progress Bars

**Sophisticated Gradient Progress**
```html
<div class="progress-bar">
    <div class="progress-fill progress-healthy" style="width: 45%"></div>
</div>
```

**Features**:
- Animated shimmer effect
- Smooth width transitions (500ms)
- Color variants: `progress-healthy`, `progress-warning`, `progress-critical`

### 5. Navigation

**Refined Nav Links**
- Gradient underline on active state
- Smooth color transitions
- Icon + text combinations
- Mobile-responsive

### 6. Tables

**Refined Data Display**
```html
<table class="table-refined">
    <thead>
        <tr>
            <th>Column 1</th>
            <th>Column 2</th>
        </tr>
    </thead>
    <tbody>
        <tr>
            <td>Data 1</td>
            <td>Data 2</td>
        </tr>
    </tbody>
</table>
```

**Features**:
- Gradient header background
- Hover row highlighting
- Consistent spacing (1rem padding)
- Uppercase headers with tracking

### 7. Forms

**Elegant Input Fields**
```html
<input type="text" class="input-refined" placeholder="Enter value...">
```

**Features**:
- Soft shadows
- Focus state with emerald glow
- Italic placeholders
- Smooth border transitions

---

## Animation System

### Timing Functions

```css
--ease-elegant: cubic-bezier(0.4, 0, 0.2, 1);  /* Smooth, refined */
--ease-bounce: cubic-bezier(0.68, -0.55, 0.265, 1.55);  /* Playful bounce */
```

### Durations

```css
--duration-fast: 150ms;   /* Micro-interactions */
--duration-base: 300ms;   /* Standard transitions */
--duration-slow: 500ms;   /* Complex animations */
```

### Staggered Reveal

Use `.stagger-item` class on elements for choreographed page load:

```html
<div class="grid">
    <div class="stagger-item">Item 1</div> <!-- Delay: 0ms -->
    <div class="stagger-item">Item 2</div> <!-- Delay: 50ms -->
    <div class="stagger-item">Item 3</div> <!-- Delay: 100ms -->
    <div class="stagger-item">Item 4</div> <!-- Delay: 150ms -->
</div>
```

### Key Animations

1. **Card Hover**: Lift (-2px) + enhanced shadow
2. **Button Hover**: Ripple effect from center
3. **Progress Bar**: Shimmer overlay animation
4. **Status Dot**: Elegant pulse (2s cycle)
5. **Modal Entry**: Slide up + fade in
6. **Skeleton Loading**: Gradient sweep animation

---

## Shadows

```css
--shadow-soft: 0 1px 3px 0 rgba(0, 0, 0, 0.04), 0 1px 2px -1px rgba(0, 0, 0, 0.04);
--shadow-card: 0 4px 6px -1px rgba(0, 0, 0, 0.06), 0 2px 4px -2px rgba(0, 0, 0, 0.06);
--shadow-elevated: 0 10px 15px -3px rgba(0, 0, 0, 0.08), 0 4px 6px -4px rgba(0, 0, 0, 0.08);
--shadow-dramatic: 0 20px 25px -5px rgba(0, 0, 0, 0.12), 0 8px 10px -6px rgba(0, 0, 0, 0.12);
```

**Usage Guidelines**:
- `shadow-soft`: Input fields, subtle elements
- `shadow-card`: Standard cards, dropdowns
- `shadow-elevated`: Hover states, important cards
- `shadow-dramatic`: Modals, overlays

---

## Spacing System

Based on 4px base unit (0.25rem):

```
0.25rem = 4px
0.5rem  = 8px
0.75rem = 12px
1rem    = 16px
1.25rem = 20px
1.5rem  = 24px
2rem    = 32px
3rem    = 48px
4rem    = 64px
```

**Common Patterns**:
- Card padding: `1.5rem` (24px)
- Button padding: `0.625rem 1.25rem` (10px 20px)
- Input padding: `0.75rem 1rem` (12px 16px)
- Section spacing: `2rem - 3rem` (32px-48px)

---

## Border Radius

```css
--radius-sm: 0.375rem;  // 6px  - Small elements, badges
--radius-md: 0.5rem;    // 8px  - Inputs, small buttons
--radius-lg: 0.75rem;   // 12px - Buttons, progress bars
--radius-xl: 1rem;      // 16px - Cards, dropdowns
--radius-2xl: 1.5rem;   // 24px - Modals, hero sections
```

---

## Layout Patterns

### Page Structure

```html
<body>
    <!-- Sticky Navigation (80px height) -->
    <nav class="bg-white/80 backdrop-blur-xl sticky top-0 z-50">
        <!-- Logo + Nav Links + User Menu -->
    </nav>

    <!-- Main Content Area -->
    <main class="py-8 lg:py-12">
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
            <!-- Page content -->
        </div>
    </main>

    <!-- Footer -->
    <footer class="border-t bg-white/40 backdrop-blur-sm">
        <!-- Footer content -->
    </footer>
</body>
```

### Dashboard Grid

```html
<!-- Stats Grid (4 columns on large screens) -->
<div class="grid grid-cols-1 gap-5 sm:grid-cols-2 lg:grid-cols-4">
    <div class="card stagger-item"><!-- Stat card --></div>
    <div class="card stagger-item"><!-- Stat card --></div>
    <div class="card stagger-item"><!-- Stat card --></div>
    <div class="card stagger-item"><!-- Stat card --></div>
</div>

<!-- Content Grid (2 columns on large screens) -->
<div class="grid grid-cols-1 gap-5 lg:grid-cols-2 mt-8">
    <div class="card"><!-- Quick actions --></div>
    <div class="card"><!-- Recent activity --></div>
</div>
```

---

## Responsive Breakpoints

```
Mobile:  < 640px  (base styles)
Tablet:  >= 640px (sm:)
Desktop: >= 768px (md:)
Large:   >= 1024px (lg:)
XL:      >= 1280px (xl:)
```

**Key Patterns**:
- Mobile-first approach (base styles = mobile)
- Stack vertically on mobile, side-by-side on tablet+
- Hide secondary content on mobile
- Hamburger menu below 640px

---

## Accessibility

### Focus States

```css
:focus-visible {
    outline: 2px solid var(--color-emerald-600);
    outline-offset: 2px;
}
```

### Reduced Motion

```css
@media (prefers-reduced-motion: reduce) {
    *,
    *::before,
    *::after {
        animation-duration: 0.01ms !important;
        animation-iteration-count: 1 !important;
        transition-duration: 0.01ms !important;
    }
}
```

### ARIA & Semantic HTML

- Use semantic HTML5 elements (`<nav>`, `<main>`, `<footer>`, `<article>`)
- Add `aria-label` to icon-only buttons
- Use `<button>` for actions, `<a>` for navigation
- Include `alt` text for all images
- Ensure sufficient color contrast (WCAG AA minimum)

---

## Implementation Guide

### Building the Assets

1. **Install dependencies**:
```bash
npm install
```

2. **Development mode** (with hot reload):
```bash
npm run dev
```

3. **Production build**:
```bash
npm run build
```

4. **Watch mode** (auto-rebuild on changes):
```bash
npm run watch
```

### Font Loading

Fonts are loaded from Google Fonts CDN with preconnect for performance:

```html
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Crimson+Pro:wght@400;500;600;700&family=DM+Sans:wght@400;500;600;700&family=JetBrains+Mono:wght@400;500&display=swap" rel="stylesheet">
```

### Tailwind Configuration

CHOM uses **Tailwind CSS v4.0** with custom theme in `resources/css/app.css`:

```css
@theme {
    --font-display: 'Crimson Pro', Georgia, serif;
    --font-sans: 'DM Sans', system-ui, sans-serif;
    --color-emerald-600: #059669;
    /* ... other custom properties */
}
```

---

## Component Examples

### VPS Health Monitor Card

```html
<div class="card stagger-item">
    <div class="card-header">
        <h2 class="font-display text-xl text-stone-900">Health Status</h2>
    </div>
    <div class="card-body">
        <!-- Status badge -->
        <div class="status-badge status-healthy mb-4">
            <span class="status-dot healthy"></span>
            Healthy
        </div>

        <!-- Resource meters -->
        <div class="space-y-3">
            <div>
                <div class="flex justify-between text-sm mb-1">
                    <span class="text-stone-600">CPU</span>
                    <span class="font-semibold text-stone-900">45%</span>
                </div>
                <div class="progress-bar">
                    <div class="progress-fill progress-healthy" style="width: 45%"></div>
                </div>
            </div>
        </div>
    </div>
</div>
```

### Action Button

```html
<button class="btn btn-primary">
    <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4"/>
    </svg>
    Create New Site
</button>
```

### Data Table

```html
<div class="card">
    <div class="card-header">
        <h2 class="font-display text-xl">Sites</h2>
    </div>
    <div class="card-body p-0">
        <table class="table-refined">
            <thead>
                <tr>
                    <th>Domain</th>
                    <th>Status</th>
                    <th>SSL</th>
                    <th>Actions</th>
                </tr>
            </thead>
            <tbody>
                <tr>
                    <td class="font-medium">example.com</td>
                    <td>
                        <span class="status-badge status-healthy">Active</span>
                    </td>
                    <td>
                        <span class="text-emerald-600 text-sm">✓ Enabled</span>
                    </td>
                    <td>
                        <button class="btn btn-secondary btn-sm">Manage</button>
                    </td>
                </tr>
            </tbody>
        </table>
    </div>
</div>
```

---

## Design Tokens Reference

### Quick Reference Chart

| Element | Font | Size | Weight | Color | Spacing |
|---------|------|------|--------|-------|---------|
| Page Title (h1) | Crimson Pro | 2.5rem | 600 | stone-900 | mb-2 |
| Section Title (h2) | Crimson Pro | 2rem | 600 | stone-900 | mb-4 |
| Subsection (h3) | Crimson Pro | 1.5rem | 600 | stone-900 | mb-3 |
| Body Text | DM Sans | 1rem | 400 | stone-700 | - |
| Label | DM Sans | 0.875rem | 500 | stone-600 | - |
| Button Text | DM Sans | 0.875rem | 500 | white/stone-700 | py-2.5 px-4 |
| Code/Mono | JetBrains Mono | 0.9em | 400 | stone-800 | - |

---

## Best Practices

### DO ✅

- Use serif headings (Crimson Pro) for all titles
- Apply stagger animations to grid items for page load
- Use jewel-tone status colors (emerald, sapphire, champagne, ruby)
- Add hover states to all interactive elements
- Use the card system for grouping related content
- Maintain generous whitespace (24px+ between sections)
- Use backdrop-blur for overlays and sticky elements
- Apply consistent border radius from the design system

### DON'T ❌

- Don't use generic blue (#3b82f6) for primary actions - use emerald (#059669)
- Don't skip animations - they define the experience
- Don't use system fonts for headings - always use Crimson Pro
- Don't use harsh shadows - keep them soft and refined
- Don't overcrowd the interface - embrace whitespace
- Don't forget mobile responsiveness
- Don't use pure black - use stone-900 (#1c1917) instead
- Don't mix different status color schemes

---

## Version History

**v2.0** (2026-01-09):
- Complete redesign with "Refined Technical Elegance" aesthetic
- New jewel-tone color palette
- Sophisticated typography system (Crimson Pro + DM Sans)
- Enhanced animation system with staggered reveals
- Premium card system with gradient accents
- Refined component library

**v1.0** (Previous):
- Standard Tailwind CSS utility design
- Generic blue color scheme
- Instrument Sans typography
- Basic card system

---

## Support & Resources

**Figma Design File**: [Coming Soon]
**Component Storybook**: [Coming Soon]
**GitHub Repository**: `/home/calounx/repositories/mentat`
**Documentation**: This file + inline code comments

---

**Designed with intention. Built with precision. Experienced with delight.**

CHOM Design System © 2026
