Vue.component('accordion', {
  data: function () {
    return {
      open: false,
      accHeight: 0
    }
  },
  props: ['header'],
  methods: {
    calculateHeight: function () {
      this.accHeight = this.$refs.accordionInner.clientHeight + 'px';
    },
    toggleOpen: function () {
      this.open = !this.open;
    }
  },
  mounted: function () {
    this.calculateHeight();
    window.addEventListener('resize', this.calculateHeight);
  },
  beforeDestroy: function () {
    window.removeEventListener('resize', this.calculateHeight);
  },
  template: '<div class="accordion"><div class="accordion-header" @click="toggleOpen"><table role="presentation"><tr><td><h4 class="no-margin inline-block">{{header}}</h4></td><td><img src="./splash/img/chevron.svg" class="inline-block" alt="expand or collapse section" :class="{\'flip\':open}"/></td></tr></table></div><div class="accordion-content" :style="{height:accHeight}" :class="{\'close\':!open}"><div class="accordion-inner" ref="accordionInner"><slot></slot></div></div></div>'
});
