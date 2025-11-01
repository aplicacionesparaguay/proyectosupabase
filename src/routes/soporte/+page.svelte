<!-- src/routes/soporte/+page.svelte -->
<script>
  // No se necesita lógica adicional
</script>

<main class="container">
  <h1>Soporte</h1>
  <section>
    <h2>¿Necesitas ayuda?</h2>
    <p>
      Nuestro equipo está disponible para resolver cualquier duda o problema con la aplicación. Contáctanos a través de los siguientes medios:
    </p>
    <ul>
      <li>Email: <a href="mailto:soporte@proyectosupabase.com">soporte@proyectosupabase.com</a></li>
      <li>Formulario: <a href="/contacto">Página de Contacto</a></li>
    </ul>
    <h2>Preguntas Frecuentes</h2>
    <p>
      Pronto publicaremos una sección de preguntas frecuentes para ayudarte con dudas comunes.
    </p>
    <a href="/" class="back-link">Volver al inicio</a>
  </section>
</main>

<style>
  .container {
    max-width: 800px;
    margin: 0 auto;
    padding: 2rem;
    font-family: Arial, sans-serif;
  }
  h1 {
    font-size: 2.5rem;
    color: #333;
    margin-bottom: 1.5rem;
  }
  h2 {
    font-size: 1.5rem;
    color: #444;
    margin-top: 2rem;
    margin-bottom: 1rem;
  }
  p {
    color: #666;
    line-height: 1.6;
    margin-bottom: 1rem;
  }
  ul {
    list-style-type: disc;
    padding-left: 1.5rem;
    margin-bottom: 1rem;
  }
  li {
    color: #666;
    margin-bottom: 0.5rem;
  }
  .back-link {
    display: inline-block;
    margin-top: 2rem;
    color: #007bff;
    text-decoration: none;
    font-weight: 500;
  }
  .back-link:hover {
    text-decoration: underline;
  }
</style>