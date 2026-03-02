var app = new Vue({
  el: '#app',
  data: {
    loginROB: false,
    registerROB: false,
    registerLink: './secure/',
    scrollUp: false,
    currentHeaderElement: undefined,
    disableHeaderHighlight: false
  },
  mounted: function() {
    this.calculateHeight();
    window.addEventListener('resize', this.calculateHeight);
    window.addEventListener('scroll', this.calculateScroll);
    setTimeout(function() {
      window.scroll();
    });

    // Make Registration URL Dependent on Environment
    const hostname = window.location.host;

    if(hostname.indexOf('conexus-test.gsa.gov') > -1) {
      this.registerLink = 'https://www.cert.eauth.usda.gov/eauth/b/conexus/registration/pivcac?finalTarget=https:%2F%2Fconexus-test.gsa.gov%2Fsecure';
    }
    else if(hostname.indexOf('conexus-cert.gsa.gov') > -1) {
      this.registerLink = 'https://www.eauth.usda.gov/eauth/b/conexus/registration/pivcac?finalTarget=https:%2F%2Fconexus-cert.gsa.gov%2Fsecure';
    }
    else if(hostname.indexOf('conexus.gsa.gov') > -1) {
      this.registerLink = 'https://www.eauth.usda.gov/eauth/b/conexus/registration/pivcac?finalTarget=https:%2F%2Fconexus.gsa.gov%2Fsecure';
    }
    // else -> is Dev (local currently skips over this page) - allow ICAM to redirect to Cert registration...
  },
  methods: {
    scrollTo: function(position) {
      var self = this;
      this.currentHeaderElement = position;
      this.disableHeaderHighlight = true;
      this.$helpers.smoothScroll(this.$refs[position].offsetTop - this.$refs.header.clientHeight, undefined, function() {
        self.disableHeaderHighlight = false;
        self.calculateScroll();
      });
    },
    calculateHeight: function() {

      this.$refs.sideInfo.style.top = this.$refs.header.clientHeight + this.$refs.sideInfo.offsetLeft;
      var innerWidth = window.innerWidth * (9 / 16);
      if (Math.abs(innerWidth - window.innerHeight) >= 50) {
        this.$refs.imageWrapper.style.height = innerWidth + 'px';
        return;
      }
      this.$refs.imageWrapper.style.height = window.innerHeight + 'px';
    },
    calculateScroll: function() {
      this.scrollUp = window.scrollY >= (window.innerHeight - this.$refs.header.clientHeight);
      this.currentHeaderElement = this.calculateCurrentHeaderElement();
    },
    calculateCurrentHeaderElement: function() {
      if (this.disableHeaderHighlight) {
        return this.currentHeaderElement;
      }
      var scrollPlusHeaderPosition = (window.scrollY + this.$refs.header.clientHeight);
      if (scrollPlusHeaderPosition >= this.$refs.help.offsetTop) {
        return 'help';
      }
      if (scrollPlusHeaderPosition >= this.$refs.links.offsetTop) {
        return 'links';
      }
      if (scrollPlusHeaderPosition >= this.$refs.features.offsetTop) {
        return 'features';
      }
      if (scrollPlusHeaderPosition >= this.$refs.about.offsetTop) {
        return 'about';
      }
      if (scrollPlusHeaderPosition >= this.$refs.login.offsetTop) {
        return 'login';
      }
    }
  }
});
