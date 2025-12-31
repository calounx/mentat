import Alpine from 'alpinejs';

// Global App Store
Alpine.store('app', {
    // User data
    user: window.userData || null,
    organization: window.organizationData || null,

    // UI State
    sidebarOpen: false,
    loading: false,

    // Methods
    setUser(user) {
        this.user = user;
    },

    setOrganization(organization) {
        this.organization = organization;
    },

    toggleSidebar() {
        this.sidebarOpen = !this.sidebarOpen;
    },

    setLoading(loading) {
        this.loading = loading;
    }
});

// Notification Store
Alpine.store('notifications', {
    items: [],
    counter: 0,

    add(notification) {
        const id = this.counter++;
        const item = {
            id,
            type: notification.type || 'info',
            title: notification.title || 'Notification',
            message: notification.message || '',
            duration: notification.duration || 5000,
            show: true
        };

        this.items.push(item);

        if (item.duration > 0) {
            setTimeout(() => {
                this.remove(id);
            }, item.duration);
        }

        return id;
    },

    remove(id) {
        const index = this.items.findIndex(item => item.id === id);
        if (index > -1) {
            this.items[index].show = false;
            setTimeout(() => {
                this.items.splice(index, 1);
            }, 100);
        }
    },

    success(title, message = '', duration = 5000) {
        return this.add({ type: 'success', title, message, duration });
    },

    error(title, message = '', duration = 5000) {
        return this.add({ type: 'error', title, message, duration });
    },

    warning(title, message = '', duration = 5000) {
        return this.add({ type: 'warning', title, message, duration });
    },

    info(title, message = '', duration = 5000) {
        return this.add({ type: 'info', title, message, duration });
    }
});

// Helper function to dispatch notifications via events
window.notify = function(type, title, message = '', duration = 5000) {
    window.dispatchEvent(new CustomEvent('notify', {
        detail: { type, title, message, duration }
    }));
};

// Convenience methods
window.notifySuccess = (title, message, duration) => window.notify('success', title, message, duration);
window.notifyError = (title, message, duration) => window.notify('error', title, message, duration);
window.notifyWarning = (title, message, duration) => window.notify('warning', title, message, duration);
window.notifyInfo = (title, message, duration) => window.notify('info', title, message, duration);

export default Alpine;
