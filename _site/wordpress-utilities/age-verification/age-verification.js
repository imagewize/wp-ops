jQuery(document).ready(function () {

  const setCookie = (name, value, days) => {
    var expires = '';
    if (days) {
      var date = new Date();
      date.setTime(date.getTime() + days * 24 * 60 * 60 * 1000);
      expires = '; expires=' + date.toUTCString();
    }
    document.cookie = name + '=' + (value || '') + expires + '; path=/';
  };

  const getCookie = (name) => {
    return (
      document.cookie
        .split('; ')
        .find((row) => row.startsWith(name + '='))
        ?.split('=')[1] || null
    );
  };
  const modal = document.querySelector('.modal-verification');
  const overlay = document.querySelector('.modal-overlayer');
  const canSeeAds = document.querySelector('#age_verify');


  const hideModal = () => {
    modal.classList.remove('modal-visible');
    overlay.classList.remove('visible');
    document.body.classList.remove('overflow-hidden');
  };

  const hideCasinoHighlightBlocks = () => {
    document.querySelectorAll('.code-block').forEach((element) => {
      if (element) {
        element.classList.add('d-none');
      }
    });
  };

  const displayCasinoHighlightBlocks = () => {
    document.querySelectorAll('.code-block').forEach((element) => {
      if (element) {
        element.classList.remove('d-none');
      }
    });
  };

  if (!getCookie('canSeeAds')) {
    modal.classList.add('modal-visible');
    overlay.classList.add('visible');
  }


  const ageButtons = ['under-18', '18-23'];
  ageButtons.forEach((id) => {
    document.getElementById(id).addEventListener('click', () => {
      setCookie('canSeeAds', 'false', 1);
      hideModal();
      hideCasinoHighlightBlocks();
    });
  });

  document.getElementById('over-24').addEventListener('click', () => {
    const advStatus = canSeeAds.checked ? 'true' : 'false';
    setCookie('canSeeAds', advStatus, 365);
    hideModal();
    if (advStatus === 'false') {
      hideCasinoHighlightBlocks();
    } else {
      displayCasinoHighlightBlocks();
    }
  });


  handleInitialCheckboxState = () => {
    const canSeeAds = getCookie('canSeeAds');
    if (canSeeAds === 'true') {
      displayCasinoHighlightBlocks();
    } else {
      hideCasinoHighlightBlocks();
    }
  };

  handleInitialCheckboxState();
});
