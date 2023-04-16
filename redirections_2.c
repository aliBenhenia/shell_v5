/* ************************************************************************** */
/*                                                                            */
/*                                                        :::      ::::::::   */
/*   redirections_2.c                                   :+:      :+:    :+:   */
/*                                                    +:+ +:+         +:+     */
/*   By: mzaroual <mzaroual@student.42.fr>          +#+  +:+       +#+        */
/*                                                +#+#+#+#+#+   +#+           */
/*   Created: 2023/04/11 00:38:42 by mazaroua          #+#    #+#             */
/*   Updated: 2023/04/12 18:15:33 by mzaroual         ###   ########.fr       */
/*                                                                            */
/* ************************************************************************** */

#include "minishell.h"

void	dup_outfile(t_redirections *redirection)
{
	int	fd;

	if (redirection->type == RIGHTRED || redirection->type == APPEND)
	{
		if (redirection->type == RIGHTRED)
			fd = open(redirection->file, O_WRONLY | O_TRUNC, 0664);
		if (redirection->type == APPEND)
			fd = open(redirection->file, O_WRONLY | O_APPEND, 0664);
		dup2(fd, 1);
		close(fd);
	}
}

void	dup_infile(t_redirections *redirection)
{
	int	fd;

	if (redirection->type == LEFTRED || redirection->type == HEREDOC)
	{
		if (redirection->type == LEFTRED)
			fd = open(redirection->file, O_RDONLY, 0777);
		else
			fd = open("heredoc", O_RDONLY, 0777);
		dup2(fd, 0);
		close(fd);
	}
}