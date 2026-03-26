    </div> <!-- End Content -->

    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
    <script>
    function toggleSidebar() { document.getElementById('sidebar').classList.toggle('active'); document.getElementById('overlay').classList.toggle('active'); }
    function closeSidebarMobile() { if (window.innerWidth < 992) toggleSidebar(); }
    function getLocation() {
        if (navigator.geolocation) {
            navigator.geolocation.getCurrentPosition(function(pos) {
                document.getElementById('koordinat').value = pos.coords.latitude + ", " + pos.coords.longitude;
            });
        } else { alert("Browser not supported"); }
    }
    </script>
</body>
</html>
<?php $conn->close(); ob_end_flush(); ?>