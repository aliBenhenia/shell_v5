#include "minishell.h"

int	count_heredocs(t_cmd_line **cmd_line)
{
	t_redirections	*redirections;
	int				count;

	redirections = (*cmd_line)->redirections;
	count = 0;
	while (redirections)
	{
		if (redirections->type == HEREDOC)
			count++;
		redirections = redirections->next;
	}
	return (count);
}

char **get_delimiters(t_cmd_line **cmd_line)
{
	t_redirections	*curr;
	char			**delimiters;
	int				i;

	curr = (*cmd_line)->redirections;
	delimiters = malloc(sizeof(char *) * (count_heredocs(cmd_line) + 1));
	i = 0;
	while (curr)
	{
		if (curr->type == HEREDOC)
			delimiters[i++] = curr->file;
		curr = curr->next;
	}
	delimiters[i] = NULL;
	return (delimiters);
}

void	heredoc_prompt(char *delimiter, int fd)
{
	char	*buffer;

	while (1337)
	{
		buffer = readline("> ");
		if (!buffer)
			break ;
		if (!(ft_strcmp(buffer, delimiter)))
			break ;
		buffer = ft_strjoin(buffer, "\n");
		write (fd, buffer, ft_strlen(buffer));
	}
}

void    ft_heredoc(t_cmd_line **cmd_line, int *fd)
{
    int 	i;
	char	**delimiters;

	i = 0;
	delimiters = get_delimiters(cmd_line);
	while (i < count_heredocs(cmd_line))
	{
		*fd = open("heredoc", O_CREAT | O_TRUNC | O_WRONLY, 0777);
		heredoc_prompt(delimiters[i], *fd);
		i++;
	}
}